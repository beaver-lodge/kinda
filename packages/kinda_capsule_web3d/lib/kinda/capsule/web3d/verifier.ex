defmodule Kinda.Capsule.Web3D.Verifier do
  @moduledoc "Four-layer Web3D verifier for live and sealed evidence."

  @behaviour Kinda.Capsule.Verifier
  @behaviour Kinda.Capsule.SealedVerifier

  alias Kinda.Capsule.{Artifact, EvidenceRef, FailureMode, Score, ScoreComponent, Verification}

  @version "web3d-four-layer@0.2.0"
  @source_digest Base.encode16(:crypto.hash(:sha256, File.read!(__ENV__.file)), case: :lower)
  @required_gates [
    "protected_inputs_integrity",
    "verifier_integrity",
    "build_and_load",
    "critical_interaction"
  ]

  @impl Kinda.Capsule.SealedVerifier
  def version, do: @version

  @impl Kinda.Capsule.SealedVerifier
  def source_digest, do: @source_digest

  @impl Kinda.Capsule.SealedVerifier
  def executable_digest do
    {__MODULE__, beam, _path} = :code.get_object_code(__MODULE__)
    beam |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  @impl Kinda.Capsule.Verifier
  def grade(%Verification{observation: %{value: result}, trace: trace}, _options)
      when is_map(result) do
    score(result, trace.artifacts)
  end

  def grade(_verification, _options), do: {:error, :missing_verification_evidence}

  @impl Kinda.Capsule.SealedVerifier
  def regrade(%{root: root, manifest: manifest}, _options) do
    artifacts = manifest["artifacts"]

    with {:ok, interaction} <- read_artifact(root, artifacts, "interaction.json"),
         {:ok, performance} <- read_artifact(root, artifacts, "performance.json"),
         {:ok, expert_review} <- read_artifact(root, artifacts, "expert-review.json"),
         {:ok, integrity} <- read_artifact(root, artifacts, "integrity.json") do
      raw = %{
        "interaction" => interaction,
        "performance" => performance,
        "expert_review" => expert_review,
        "integrity" => integrity
      }

      score(raw, artifacts)
    end
  end

  defp score(raw, artifacts) do
    gates = gates(raw)
    passed? = Enum.all?(gates, fn {_gate, value} -> value == :pass end)

    interaction = interaction_score(raw)
    performance = performance_score(raw)
    expert = expert_score(raw)

    total =
      if passed?,
        do: Float.round(interaction * 0.4 + performance * 0.3 + expert * 0.3, 3),
        else: 0.0

    {:ok,
     %Score{
       value: total,
       gates: gates,
       components: %{
         interaction: %ScoreComponent{
           value: interaction,
           evidence:
             evidence(artifacts, "interaction.json") ++ evidence(artifacts, "interaction.webm")
         },
         performance: %ScoreComponent{
           value: performance,
           evidence: evidence(artifacts, "performance.json")
         },
         expert: %ScoreComponent{value: expert, evidence: evidence(artifacts, "after.png")}
       },
       failure_modes: failure_modes(raw, artifacts),
       metadata: %{
         verifier_version: @version,
         required_gates_passed?: passed?,
         expert_review: :illustrative
       }
     }}
  end

  defp gates(raw) do
    values = %{
      "protected_inputs_integrity" => get_in(raw, ["integrity", "protected_inputs"]) == true,
      "verifier_integrity" => get_in(raw, ["integrity", "verifier"]) == true,
      "build_and_load" => build_and_load?(raw),
      "critical_interaction" => critical_interaction?(raw)
    }

    Map.new(@required_gates, fn gate ->
      {gate, if(Map.fetch!(values, gate), do: :pass, else: :fail)}
    end)
  end

  defp build_and_load?(raw) do
    get_in(raw, ["interaction", "consoleErrors"]) == []
  end

  defp critical_interaction?(raw) do
    initial = get_in(raw, ["interaction", "initial"]) || %{}
    after_drag = get_in(raw, ["interaction", "afterDrag"]) || %{}
    after_zoom = get_in(raw, ["interaction", "afterZoom"]) || %{}
    after_resize = get_in(raw, ["interaction", "afterResize"]) || %{}
    final = get_in(raw, ["interaction", "final"]) || %{}

    valid_camera_distance?(after_zoom) and rotation_changed?(initial, after_drag) and
      projected_after_resize?(after_resize) and completed_accessible_interaction?(final)
  end

  defp interaction_score(raw), do: if(critical_interaction?(raw), do: 0.88, else: 0.0)

  defp performance_score(raw) do
    performance = raw["performance"] || %{}

    if performance["renderAllocations"] == 0 and below?(performance["frameP95"], 40),
      do: 0.91,
      else: 0.55
  end

  defp expert_score(raw) do
    case get_in(raw, ["expert_review", "score"]) do
      score when is_number(score) -> max(0.0, min(score / 1, 1.0))
      _score -> 0.0
    end
  end

  defp failure_modes(raw, artifacts) do
    raw
    |> get_in(["expert_review", "findings"])
    |> List.wrap()
    |> Enum.map(fn failure ->
      %FailureMode{
        code: Map.get(failure, "code", "unspecified"),
        message: Map.get(failure, "message", "Unspecified verifier failure"),
        severity: severity(Map.get(failure, "severity")),
        evidence:
          evidence(
            artifacts,
            Map.get(failure, "artifact"),
            Map.get(failure, "fragment")
          ),
        metadata: Map.drop(failure, ["code", "message", "severity", "artifact", "fragment"])
      }
    end)
  end

  defp read_artifact(root, artifacts, name) do
    case Enum.find(artifacts, &(&1["name"] == name)) do
      nil ->
        {:error, {:missing_evidence, name}}

      artifact ->
        with {:ok, encoded} <- File.read(Path.join(root, artifact["path"])),
             do: JSON.decode(encoded)
    end
  end

  defp valid_camera_distance?(snapshot) do
    distance = snapshot["cameraDistance"]
    is_number(distance) and distance >= 2.5 and distance <= 6.2
  end

  defp rotation_changed?(initial, after_drag) do
    get_in(after_drag, ["rotation", "y"]) != get_in(initial, ["rotation", "y"])
  end

  defp projected_after_resize?(snapshot), do: positive?(snapshot["projectionUpdates"])

  defp completed_accessible_interaction?(snapshot) do
    positive?(snapshot["hotspotClicks"]) and snapshot["reducedMotion"] == true
  end

  defp positive?(value), do: is_number(value) and value > 0
  defp below?(value, threshold), do: is_number(value) and value < threshold

  defp evidence(artifacts, name, fragment \\ nil)
  defp evidence(_artifacts, nil, _fragment), do: []

  defp evidence(artifacts, name, fragment) do
    case Enum.find(artifacts || [], &(artifact_name(&1) == name)) do
      nil -> []
      artifact -> [%EvidenceRef{artifact: artifact_id(artifact), fragment: fragment}]
    end
  end

  defp artifact_name(%Artifact{name: name}), do: name
  defp artifact_name(%{"name" => name}), do: name
  defp artifact_name(_artifact), do: nil

  defp artifact_id(%Artifact{id: id}), do: id
  defp artifact_id(%{"id" => id}), do: id

  defp severity("critical"), do: :critical
  defp severity("info"), do: :info
  defp severity(_severity), do: :warning
end
