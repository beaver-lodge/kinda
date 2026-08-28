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
    workspace = state.workspace
    verification = Path.join([workspace, "artifacts", "verification.json"])

    case File.read(verification) do
      {:ok, encoded} ->
        case JSON.decode(encoded) do
          {:ok, result} ->
            result = enforce_integrity_gates(result, state)
            digest = encoded |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

            {:ok,
             %Observation{
               value: result,
               metadata: %{status: :verified},
               evidence: [%EvidenceRef{artifact: digest}]
             }}

          {:error, reason} ->
            {:error, {:invalid_verification, reason}}
        end

      {:error, :enoent} ->
        {:ok, observation(workspace, :ready)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def close(_context, _state), do: :ok

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

  defp enforce_integrity_gates(result, state) do
    fixture_digest = digest_file(Path.join(state.workspace, "package-lock.json"))
    verifier_digest = get_in(result, ["runtime", "verifierDigest"])

    result
    |> put_in(["gates", "fixture_integrity"], fixture_digest == state.protected_digest)
    |> put_in(
      ["gates", "verifier_integrity"],
      verifier_digest == state.browser_verifier_digest
    )
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
