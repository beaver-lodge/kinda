defmodule Kinda.Capsule.Web3D.Task do
  @moduledoc false

  @behaviour Kinda.Capsule.Task

  alias Kinda.Capsule.{EvidenceRef, Observation}
  alias Kinda.Sandbox

  @impl true
  def reset(context, _seed, options) do
    fixture = Keyword.fetch!(options, :fixture)
    protected_digest = Keyword.fetch!(options, :protected_digest)
    browser_verifier_digest = Keyword.fetch!(options, :browser_verifier_digest)

    with {:ok, workspace} <- workspace(context.sandbox),
         {:ok, copied} <- copy_fixture(fixture, workspace) do
      state = %{
        workspace: workspace,
        evidence_directory:
          Keyword.get(options, :evidence_directory) || Path.join(workspace, "artifacts"),
        copied: copied,
        protected_digest: protected_digest,
        browser_verifier_digest: browser_verifier_digest
      }

      {:ok, state, observation(workspace, :ready)}
    else
      {:error, reason, path} -> {:error, {:fixture_copy_failed, path, reason}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def observe(_context, state) do
    with {:ok, interaction, interaction_ref} <-
           read_evidence(state.evidence_directory, "interaction.json"),
         {:ok, performance, performance_ref} <-
           read_evidence(state.evidence_directory, "performance.json"),
         {:ok, expert_review, expert_ref} <-
           read_evidence(state.evidence_directory, "expert-review.json"),
         {:ok, _browser, browser_ref} <- read_evidence(state.evidence_directory, "browser.json"),
         {:ok, integrity, integrity_ref} <-
           read_evidence(state.evidence_directory, "integrity.json") do
      {:ok,
       %Observation{
         value: %{
           "interaction" => interaction,
           "performance" => performance,
           "expert_review" => expert_review,
           "integrity" => integrity
         },
         metadata: %{status: :verified},
         evidence: [interaction_ref, performance_ref, expert_ref, browser_ref, integrity_ref]
       }}
    else
      {:error, :enoent} -> {:ok, observation(state.workspace, :ready)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def close(_context, _state), do: :ok

  @doc false
  @spec write_integrity_evidence(binary(), keyword()) :: :ok | {:error, term()}
  def write_integrity_evidence(workspace, options) do
    protected_digest = Keyword.fetch!(options, :protected_digest)
    browser_verifier_digest = Keyword.fetch!(options, :browser_verifier_digest)

    evidence_directory =
      Keyword.get(options, :evidence_directory) || Path.join(workspace, "artifacts")

    browser_evidence = Path.join(evidence_directory, "browser.json")

    with {:ok, encoded} <- read_browser_evidence(browser_evidence),
         {:ok, browser} <- JSON.decode(encoded) do
      fixture_digest = digest_file(Path.join(workspace, "package-lock.json"))
      verifier_digest = browser["verifier_digest"]

      evidence = %{
        "fixture" => fixture_digest == protected_digest,
        "verifier" => verifier_digest == browser_verifier_digest,
        "fixture_expected" => protected_digest,
        "fixture_actual" => fixture_digest,
        "verifier_expected" => browser_verifier_digest,
        "verifier_actual" => verifier_digest,
        "produced_by" => "kinda-capsule-trusted-task@0.1.0"
      }

      File.write(
        Path.join(evidence_directory, "integrity.json"),
        JSON.encode!(evidence)
      )
    end
  end

  defp read_browser_evidence(path) do
    case File.read(path) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, reason} -> {:error, {:browser_evidence_unavailable, path, reason}}
    end
  end

  defp observation(workspace, status) do
    %Observation{value: %{"status" => to_string(status), "workspace" => workspace}}
  end

  defp copy_fixture(fixture, workspace) do
    fixture
    |> File.ls!()
    |> Enum.reject(&(&1 in ["artifacts", "dist", "node_modules", "tests"]))
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, copied} ->
      source = Path.join(fixture, entry)
      target = Path.join(workspace, entry)

      case File.cp_r(source, target) do
        {:ok, paths} -> {:cont, {:ok, copied ++ paths}}
        {:error, reason, path} -> {:halt, {:error, reason, path}}
      end
    end)
  rescue
    exception in File.Error -> {:error, exception.reason}
  end

  defp workspace(sandbox) do
    command = %Sandbox.Command.Spec{
      executable: erl(),
      args: ["-noshell", "-eval", "{ok,C}=file:get_cwd(),io:put_chars(C),halt()."],
      env: %{"LANG" => "C.UTF-8"},
      inherit_env: runtime_env()
    }

    with {:ok, %{termination: {:exit, 0}, stdout: output}} <-
           Sandbox.Command.run(sandbox, command) do
      {:ok, String.trim(output)}
    end
  end

  defp erl, do: System.find_executable("erl") || raise("erl executable unavailable")

  defp read_evidence(evidence_directory, name) do
    path = Path.join(evidence_directory, name)

    with {:ok, encoded} <- File.read(path),
         {:ok, value} <- JSON.decode(encoded) do
      digest = encoded |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
      {:ok, value, %EvidenceRef{artifact: digest}}
    else
      {:error, :enoent} -> {:error, :enoent}
      {:error, reason} -> {:error, {:invalid_evidence, name, reason}}
    end
  end

  defp digest_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        contents |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

      {:error, _reason} ->
        nil
    end
  end

  defp runtime_env do
    ["PATH", "SYSTEMROOT", "SystemRoot", "COMSPEC", "ComSpec", "PATHEXT", "TEMP", "TMP"]
  end
end
