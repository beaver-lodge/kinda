defmodule Kinda.Capsule.Web3D.Verifier do
  @moduledoc "Four-layer Web3D verifier for live and sealed evidence."

  @behaviour Kinda.Capsule.Verifier
  @behaviour Kinda.Capsule.SealedVerifier

  alias Kinda.Capsule.{Artifact, EvidenceRef, FailureMode, Score, ScoreComponent, Verification}

  @version "web3d-four-layer@0.1.0"
  @required_gates [
    "fixture_integrity",
    "verifier_integrity",
    "build_and_load",
    "critical_interaction"
  ]

  @impl Kinda.Capsule.SealedVerifier
  def version, do: @version

  @impl Kinda.Capsule.SealedVerifier
  def digest do
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
    case Enum.find(manifest["artifacts"], &(&1["name"] == "verification.json")) do
      nil ->
        {:error, :missing_verification_evidence}

      artifact ->
        with {:ok, encoded} <- File.read(Path.join(root, artifact["path"])),
             {:ok, result} <- JSON.decode(encoded) do
          score(result, manifest["artifacts"])
        end
    end
  end

  defp score(result, artifacts) do
    gates = Map.new(@required_gates, fn gate -> {gate, gate_result(result, gate)} end)
    passed? = Enum.all?(gates, fn {_gate, value} -> value == :pass end)

    interaction = metric(result, "interaction", 0.0)
    performance = metric(result, "performance", 0.0)
    expert = metric(result, "expert", 0.0)

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
       failure_modes: failure_modes(result, artifacts),
       metadata: %{verifier_version: @version, required_gates_passed?: passed?}
     }}
  end

  defp gate_result(result, gate) do
    if get_in(result, ["gates", gate]) == true, do: :pass, else: :fail
  end

  defp metric(result, name, fallback) do
    case get_in(result, ["scores", name]) do
      value when is_number(value) -> max(0.0, min(value / 1, 1.0))
      _value -> fallback
    end
  end

  defp failure_modes(result, artifacts) do
    result
    |> Map.get("failure_modes", [])
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
