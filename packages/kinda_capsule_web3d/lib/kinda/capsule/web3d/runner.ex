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
        run_episode(capsule, bundle, index)
      after
        Capsule.close(capsule)
      end
    end
  end

  defp run_episode(capsule, bundle, index) do
    with {:ok, %{value: %{"workspace" => workspace}}} <- Capsule.reset(capsule, seed: "showcase"),
         {:ok, %{termination: {:exit, 0}}} <-
           Capsule.execute(capsule, action(npm(), ["ci"], "install"), :infinity),
         {:ok, %{termination: {:exit, 0}}} <-
           Capsule.execute(
             capsule,
             action(node_executable(), [browser_verifier(), "."], "verify"),
             :infinity
           ),
         {:ok, sources} <- attach_artifacts(capsule, workspace),
         {:ok, score} <- Capsule.grade(capsule),
         {:ok, trace} <- Capsule.trace(capsule),
         {:ok, digest} <- Bundle.export(trace, bundle, artifact_sources: sources),
         :ok <- EventIndex.record(index, trace, digest) do
      {:ok, %{bundle: bundle, index: index, digest: digest, score: score, episode: trace.episode}}
    end
  end

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
      {"verification.json", :metrics, "application/json"}
    ]

    Enum.reduce_while(artifacts, {:ok, %{}}, fn {name, kind, media_type}, {:ok, sources} ->
      relative = Path.join("artifacts", name)

      with {:ok, artifact} <-
             Artifact.from_file(workspace, relative,
               name: name,
               kind: kind,
               media_type: media_type,
               produced_by: %{step: 1, verifier: Web3D.verifier_version()}
             ),
           :ok <- Capsule.attach_artifact(capsule, artifact) do
        source = Path.join(workspace, relative)
        {:cont, {:ok, Map.put(sources, artifact.id, source)}}
      else
        error -> {:halt, error}
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
