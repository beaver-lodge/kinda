defmodule Kinda.Capsule.Web3D.Runner do
  @moduledoc "Runs the showcase fixture as a Capsule episode and exports its evidence bundle."

  alias Kinda.Capsule
  alias Kinda.Capsule.Action.Command
  alias Kinda.Capsule.{Artifact, Bundle}
  alias Kinda.Capsule.Web3D
  alias Kinda.Capsule.Web3D.EventIndex
  alias Kinda.Sandbox

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(options) do
    bundle = Keyword.fetch!(options, :bundle)
    index = Keyword.get(options, :index, bundle <> ".sqlite3")
    spec = Web3D.spec(options)

    with {:ok, capsule} <- Capsule.create(spec) do
      try do
        run_episode(capsule, bundle, index, spec.task_options)
      after
        Capsule.close(capsule)
      end
    end
  end

  defp run_episode(capsule, bundle, index, task_options) do
    with {:ok, %{value: %{"workspace" => workspace}}} <- Capsule.reset(capsule, seed: "showcase"),
         :ok <- execute(capsule, action(npm(), ["ci"], "install"), "install"),
         :ok <-
           execute(
             capsule,
             action(node_executable(), [browser_verifier(), workspace], "verify"),
             "verify"
           ),
         :ok <-
           stage(
             "integrity",
             Kinda.Capsule.Web3D.Task.write_integrity_evidence(workspace, task_options)
           ),
         {:ok, sources} <- attach_artifacts(capsule, workspace),
         {:ok, score} <- Capsule.grade(capsule),
         {:ok, trace} <- Capsule.trace(capsule),
         {:ok, digest} <- Bundle.export(trace, bundle, artifact_sources: sources),
         :ok <- stage("event_index", EventIndex.record(index, trace, digest)) do
      {:ok, %{bundle: bundle, index: index, digest: digest, score: score, episode: trace.episode}}
    end
  end

  defp execute(capsule, action, phase) do
    case Capsule.execute(capsule, action, :infinity) do
      {:ok, %{termination: {:exit, 0}}} -> :ok
      {:ok, result} -> {:error, {:command_failed, phase, result.termination, result.stderr}}
      {:error, error} -> {:error, {:command_error, phase, error}}
    end
  end

  defp stage(_stage, :ok), do: :ok
  defp stage(stage, {:error, reason}), do: {:error, {:stage_failed, stage, reason}}

  defp action(executable, args, phase) do
    %Command{
      spec: %Sandbox.Command.Spec{
        executable: executable,
        args: args,
        inherit_env: runtime_env(),
        timeout: 180_000,
        terminate_after: 2_000,
        max_output_bytes: 2_000_000
      },
      metadata: %{phase: phase}
    }
  end

  defp attach_artifacts(capsule, workspace) do
    artifacts = [
      {"before.png", :image, "image/png"},
      {"after.png", :image, "image/png"},
      {"interaction.webm", :video, "video/webm"},
      {"interaction.json", :trace, "application/json"},
      {"performance.json", :metrics, "application/json"},
      {"expert-review.json", :document, "application/json"},
      {"browser.json", :metrics, "application/json"},
      {"integrity.json", :metrics, "application/json"}
    ]

    Enum.reduce_while(artifacts, {:ok, %{}}, fn {name, kind, media_type}, {:ok, sources} ->
      relative = Path.join("artifacts", name)

      with {:ok, artifact} <-
             Artifact.from_file(workspace, relative,
               name: name,
               kind: kind,
               media_type: media_type,
               produced_by: %{verifier: Web3D.verifier_version()}
             ),
           :ok <- Capsule.attach_artifact(capsule, artifact) do
        source = Path.join(workspace, relative)
        {:cont, {:ok, Map.put(sources, artifact.id, source)}}
      else
        {:error, reason} -> {:halt, {:error, {:artifact_unavailable, name, reason}}}
      end
    end)
  end

  defp runtime_env do
    ["PATH", "SYSTEMROOT", "SystemRoot", "COMSPEC", "ComSpec", "PATHEXT", "TEMP", "TMP"]
  end

  defp npm, do: System.find_executable("npm") || raise("npm executable unavailable")

  defp node_executable,
    do: System.find_executable("node") || raise("node executable unavailable")

  defp browser_verifier do
    Path.join(Web3D.fixture_root(), "tests/verify.mjs")
  end
end
