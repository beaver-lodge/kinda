defmodule Kinda.Capsule.BundleTest do
  use ExUnit.Case, async: true

  alias Kinda.Capsule.{Artifact, Bundle, Episode, RuntimeFingerprint, Score, Trace}

  defmodule Regrader do
    @behaviour Kinda.Capsule.SealedVerifier

    @impl true
    def version, do: "verifier@1"

    @impl true
    def source_digest, do: "verifier-source-sha256"

    @impl true
    def executable_digest, do: "verifier-executable-sha256"

    @impl true
    def regrade(%{root: root}, _options) do
      with {:ok, encoded} <- File.read(Path.join(root, "artifacts/evidence.json")),
           {:ok, %{"quality" => quality}} <- JSON.decode(encoded) do
        {:ok, %Score{value: quality}}
      end
    end
  end

  defmodule SourceEquivalentRegrader do
    @behaviour Kinda.Capsule.SealedVerifier

    alias Kinda.Capsule.BundleTest.Regrader

    @impl true
    def version, do: Regrader.version()

    @impl true
    def source_digest, do: Regrader.source_digest()

    @impl true
    def executable_digest, do: "different-local-build"

    @impl true
    def regrade(bundle, options), do: Regrader.regrade(bundle, options)
  end

  @tag :tmp_dir
  test "exports, verifies, and regrades sealed evidence", %{tmp_dir: tmp_dir} do
    source = Path.join(tmp_dir, "evidence.json")
    File.write!(source, JSON.encode!(%{quality: 0.75}))
    {:ok, artifact} = Artifact.from_file(tmp_dir, "evidence.json", name: "evidence.json")
    destination = Path.join(tmp_dir, "episode")

    assert {:ok, digest} =
             Bundle.export(trace(artifact), destination,
               artifact_sources: %{artifact.id => source}
             )

    assert is_binary(digest)
    assert {:ok, %{"bundle_digest" => ^digest}} = Bundle.verify(destination)
    assert {:ok, %Score{value: 0.75}} = Bundle.regrade(destination, Regrader)

    assert {:ok, %Score{value: 0.75}} =
             Bundle.regrade(destination, Regrader, identity: :exact)

    assert {:ok, %Score{value: 0.75}} =
             Bundle.regrade(destination, SourceEquivalentRegrader)

    assert {:error, %Kinda.Capsule.Error{reason: :verifier_failure}} =
             Bundle.regrade(destination, SourceEquivalentRegrader, identity: :exact)
  end

  @tag :tmp_dir
  test "failed exports leave no partial destination and can be retried", %{tmp_dir: tmp_dir} do
    source = Path.join(tmp_dir, "evidence.json")
    File.write!(source, JSON.encode!(%{quality: 0.75}))
    {:ok, artifact} = Artifact.from_file(tmp_dir, "evidence.json", name: "evidence.json")
    destination = Path.join(tmp_dir, "episode")
    invalid = %{artifact | path: "artifacts/#{String.duplicate("x", 256)}"}

    assert {:error, %Kinda.Capsule.Error{reason: :filesystem_failure}} =
             Bundle.export(trace(invalid), destination, artifact_sources: %{invalid.id => source})

    refute File.exists?(destination)
    assert Path.wildcard(Path.join(tmp_dir, ".episode.tmp-*")) == []

    assert {:ok, _digest} =
             Bundle.export(trace(artifact), destination,
               artifact_sources: %{artifact.id => source}
             )
  end

  @tag :tmp_dir
  test "tampering with sealed evidence fails closed", %{tmp_dir: tmp_dir} do
    source = Path.join(tmp_dir, "evidence.json")
    File.write!(source, JSON.encode!(%{quality: 0.75}))
    {:ok, artifact} = Artifact.from_file(tmp_dir, "evidence.json", name: "evidence.json")
    destination = Path.join(tmp_dir, "episode")

    {:ok, _digest} =
      Bundle.export(trace(artifact), destination, artifact_sources: %{artifact.id => source})

    File.write!(Path.join(destination, "artifacts/evidence.json"), "tampered")

    assert {:error, %Kinda.Capsule.Error{reason: :invalid_bundle}} = Bundle.verify(destination)
  end

  defp trace(artifact) do
    episode = %Episode{
      capsule_id: "capsule-1",
      episode_id: "episode-1",
      capsule_version: "capsule@1",
      task_version: "task@1",
      fixture_digest: "fixture-sha256",
      verifier_version: Regrader.version(),
      verifier_source_digest: Regrader.source_digest(),
      verifier_executable_digest: Regrader.executable_digest(),
      runtime: %RuntimeFingerprint{}
    }

    %Trace{
      capsule_id: episode.capsule_id,
      episode_id: episode.episode_id,
      task_version: episode.task_version,
      verifier_version: episode.verifier_version,
      seed: 42,
      episode: episode,
      artifacts: [artifact],
      score: %Score{value: 0.75}
    }
  end
end
