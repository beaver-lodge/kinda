defmodule Kinda.Capsule.Web3D do
  @moduledoc "A command-backed Web3D evaluation task and exportable episode showcase."

  alias Kinda.Capsule.{RuntimeFingerprint, SandboxSpec, Spec}
  alias Kinda.Capsule.Web3D.{Task, Verifier}
  alias Kinda.Sandbox.Backend.LocalProcess

  @task_version "web3d-viewer-repair@0.1.0"
  @verifier_version "web3d-four-layer@0.2.0"

  @spec spec(keyword()) :: Spec.t()
  def spec(options) do
    fixture = Keyword.get(options, :fixture, fixture_root())
    parent = Keyword.fetch!(options, :parent_directory)

    %Spec{
      task: Task,
      task_version: @task_version,
      task_options: [
        fixture: fixture,
        evidence_directory: Keyword.get(options, :evidence_directory),
        protected_inputs: %{
          "package-lock.json" => digest_file(Path.join(fixture, "package-lock.json"))
        },
        browser_verifier_digest: digest_file(Path.join(fixture, "tests/verify.mjs"))
      ],
      verifier: Verifier,
      verifier_version: @verifier_version,
      verifier_source_digest: Verifier.source_digest(),
      verifier_executable_digest: Verifier.executable_digest(),
      verifier_options: [],
      fixture_digest: digest_tree(fixture),
      runtime: Keyword.get(options, :runtime, default_runtime()),
      model: Keyword.get(options, :model, %{}),
      sandbox: %SandboxSpec{
        backend: LocalProcess,
        backend_spec: %LocalProcess.Spec{parent_directory: parent}
      },
      max_steps: 8
    }
  end

  @spec fixture_root() :: binary()
  def fixture_root, do: Application.app_dir(:kinda_capsule_web3d, "priv/web3d")

  @spec verifier_version() :: binary()
  def verifier_version, do: @verifier_version

  @spec digest_tree(binary()) :: binary()
  def digest_tree(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.reject(&String.contains?(&1, "node_modules"))
    |> Enum.sort()
    |> Enum.map_join(fn path -> Path.relative_to(path, root) <> <<0>> <> File.read!(path) end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp digest_file(path) do
    path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  defp default_runtime do
    %RuntimeFingerprint{
      browser: "Chromium (Playwright; resolved in browser.json)",
      os: runtime_architecture(),
      viewport: %{width: 1440, height: 900},
      device_pixel_ratio: 1,
      cache_policy: "cold fixture, fixed warm-up",
      metadata: %{
        interaction_script: "web3d-interaction@0.1.0",
        runtime_evidence: "browser.json",
        headless: true,
        gpu_mode: "playwright-headless-default",
        timing_policy: %{warmup_frames: 120, sample_frames: 120, frame_timeout_ms: 30_000}
      }
    }
  end

  defp runtime_architecture do
    os = :os.type() |> Tuple.to_list() |> Enum.join("/")
    "#{os}/#{:erlang.system_info(:system_architecture)}"
  end
end
