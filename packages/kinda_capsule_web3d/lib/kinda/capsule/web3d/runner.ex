defmodule Kinda.Capsule.Web3D.Runner do
  @moduledoc "Runs the showcase fixture as a Capsule episode and exports its evidence bundle."

  alias Kinda.Capsule
  alias Kinda.Capsule.Action.Command
  alias Kinda.Capsule.{Artifact, Bundle}
  alias Kinda.Capsule.Web3D
  alias Kinda.Capsule.Web3D.EventIndex
  alias Kinda.Sandbox

  @browser_artifacts [
    "before.png",
    "after.png",
    "interaction.webm",
    "interaction.json",
    "performance.json",
    "expert-review.json",
    "browser.json"
  ]

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(options) do
    bundle = Keyword.fetch!(options, :bundle)
    index = Keyword.get(options, :index, bundle <> ".sqlite3")
    evidence = evidence_directory(bundle)
    spec = Web3D.spec(Keyword.put(options, :evidence_directory, evidence))

    with :ok <- File.mkdir_p(evidence) do
      try do
        with {:ok, capsule} <- Capsule.create(spec) do
          try do
            run_episode(capsule, bundle, index, evidence, spec.task_options)
          after
            Capsule.close(capsule)
          end
        end
      after
        File.rm_rf(evidence)
      end
    end
  end

  defp run_episode(capsule, bundle, index, evidence, task_options) do
    with {:ok, %{value: %{"workspace" => workspace}}} <- Capsule.reset(capsule, seed: "showcase"),
         {:ok, _install} <- execute(capsule, action(npm(), ["ci"], "install"), "install"),
         {:ok, _verification} <- execute_verification(capsule, workspace, evidence),
         :ok <-
           stage(
             "integrity",
             Kinda.Capsule.Web3D.Task.write_integrity_evidence(workspace, task_options)
           ),
         {:ok, sources} <- attach_artifacts(capsule, evidence),
         {:ok, score} <- Capsule.grade(capsule),
         {:ok, trace} <- Capsule.trace(capsule),
         {:ok, digest} <- Bundle.export(trace, bundle, artifact_sources: sources),
         :ok <- stage("event_index", EventIndex.record(index, trace, digest)) do
      {:ok, %{bundle: bundle, index: index, digest: digest, score: score, episode: trace.episode}}
    end
  end

  defp execute(capsule, action, phase) do
    case Capsule.execute(capsule, action, :infinity) do
      {:ok, %{termination: {:exit, 0}} = result} -> {:ok, result}
      {:ok, result} -> {:error, {:command_failed, phase, result.termination, result.stderr}}
      {:error, error} -> {:error, {:command_error, phase, error}}
    end
  end

  defp execute_verification(capsule, workspace, evidence) do
    source = Path.join(workspace, ".kinda-web3d-evidence")

    with {:ok, execution} <-
           Capsule.start(
             capsule,
             action(node_executable(), [browser_verifier(), workspace, source], "verify")
           ) do
      await_and_project_verification(capsule, execution, source, evidence)
    end
  end

  defp await_and_project_verification(capsule, execution, source, evidence) do
    result =
      with :ok <-
             stage(
               "evidence_ready",
               await_evidence(capsule, execution, Path.join(source, ".ready"), 180_000)
             ),
           :ok <- stage("evidence_projection", copy_evidence(source, evidence)),
           :ok <- File.write(Path.join(source, ".ack"), "ok") do
        case Capsule.await(execution, :infinity) do
          {:ok, %{termination: {:exit, 0}} = command_result} ->
            {:ok, command_result}

          {:ok, command_result} ->
            {:error,
             {:command_failed, "verify", command_result.termination, command_result.stderr}}

          {:error, error} ->
            {:error, {:command_error, "verify", error}}
        end
      end

    if match?({:error, _reason}, result), do: Capsule.cancel(execution)
    result
  end

  defp stage(_stage, :ok), do: :ok
  defp stage(stage, {:error, reason}), do: {:error, {:stage_failed, stage, reason}}

  defp evidence_directory(bundle) do
    id = System.unique_integer([:positive, :monotonic])
    Path.join(Path.dirname(Path.expand(bundle)), ".kinda-web3d-evidence-#{id}")
  end

  defp copy_evidence(source, destination) do
    Enum.reduce_while(@browser_artifacts, :ok, fn name, :ok ->
      case File.cp(Path.join(source, name), Path.join(destination, name)) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:unavailable_artifact, name, reason}}}
      end
    end)
  end

  defp await_evidence(capsule, execution, path, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_evidence_until(capsule, execution, path, deadline)
  end

  defp await_evidence_until(capsule, execution, path, deadline) do
    cond do
      File.regular?(path) ->
        :ok

      verification_finished?(capsule) ->
        early_verification_exit(execution)

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, {:timeout, path}}

      true ->
        Process.sleep(25)
        await_evidence_until(capsule, execution, path, deadline)
    end
  end

  defp verification_finished?(capsule) do
    case Capsule.trace(capsule) do
      {:ok, %{steps: steps}} -> match?(%{metadata: %{phase: "verify"}}, List.last(steps))
      _result -> false
    end
  end

  defp early_verification_exit(execution) do
    case Capsule.await(execution, :infinity) do
      {:ok, result} ->
        {:error,
         {:verifier_exited_before_evidence, result.termination, result.stderr,
          byte_size(result.stdout)}}

      {:error, error} ->
        {:error, {:command_error, "verify", error}}
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

  defp attach_artifacts(capsule, evidence) do
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
      with {:ok, artifact} <-
             Artifact.from_file(evidence, name,
               name: name,
               kind: kind,
               media_type: media_type,
               produced_by: %{verifier: Web3D.verifier_version()}
             ),
           :ok <- Capsule.attach_artifact(capsule, artifact) do
        source = Path.join(evidence, name)
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
