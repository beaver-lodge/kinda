defmodule Kinda.Capsule.Web3D.VerifierTest do
  use ExUnit.Case, async: true

  alias Kinda.Capsule.{Artifact, Episode, Observation, RuntimeFingerprint, Trace, Verification}
  alias Kinda.Capsule.Web3D.Verifier

  test "gates scoring dimensions and binds judgments to evidence" do
    artifacts = [
      artifact("interaction.json"),
      artifact("interaction.webm"),
      artifact("performance.json"),
      artifact("expert-review.json"),
      artifact("after.png")
    ]

    episode = episode()

    verification = %Verification{
      capsule_id: episode.capsule_id,
      episode_id: episode.episode_id,
      task_version: episode.task_version,
      verifier_version: episode.verifier_version,
      seed: 1,
      observation: %Observation{value: result()},
      trace: trace(episode, artifacts),
      episode: episode
    }

    assert {:ok, score} = Verifier.grade(verification, [])
    assert score.value == 0.835
    assert score.gates["critical_interaction"] == :pass
    assert length(score.components.interaction.evidence) == 2
    assert [%{fragment: "final"}] = hd(score.failure_modes).evidence
  end

  test "a failed required gate zeroes the continuous score" do
    episode = episode()
    failed = put_in(result(), ["interaction", "consoleErrors"], ["load failed"])

    verification = %Verification{
      capsule_id: episode.capsule_id,
      episode_id: episode.episode_id,
      task_version: episode.task_version,
      verifier_version: episode.verifier_version,
      seed: 1,
      observation: %Observation{value: failed},
      trace: trace(episode, []),
      episode: episode
    }

    assert {:ok, score} = Verifier.grade(verification, [])
    assert score.value == 0.0
    refute score.metadata.required_gates_passed?
  end

  @tag :tmp_dir
  test "sealed regrade recomputes from raw domain evidence", %{tmp_dir: tmp_dir} do
    artifacts = Path.join(tmp_dir, "artifacts")
    File.mkdir!(artifacts)
    raw = result()

    entries = [
      write_artifact(artifacts, "interaction.json", raw["interaction"]),
      write_artifact(artifacts, "performance.json", raw["performance"]),
      write_artifact(artifacts, "expert-review.json", raw["expert_review"]),
      write_artifact(artifacts, "integrity.json", raw["integrity"]),
      artifact_entry("interaction.webm"),
      artifact_entry("after.png")
    ]

    assert {:ok, score} =
             Verifier.regrade(%{root: tmp_dir, manifest: %{"artifacts" => entries}}, [])

    assert score.value == 0.835
    assert score.metadata.expert_review == :illustrative
    assert score.components.performance.value == 0.91
  end

  defp result do
    %{
      "integrity" => %{"fixture" => true, "verifier" => true},
      "interaction" => %{
        "consoleErrors" => [],
        "initial" => %{"rotation" => %{"y" => 0.1}},
        "afterDrag" => %{"rotation" => %{"y" => 0.8}},
        "afterZoom" => %{"cameraDistance" => 6.2},
        "afterResize" => %{"projectionUpdates" => 1},
        "final" => %{
          "hotspotClicks" => 1,
          "reducedMotion" => true
        }
      },
      "performance" => %{"renderAllocations" => 0, "frameP95" => 17.0},
      "expert_review" => %{
        "version" => "web3d-expert-illustrative@0.1.0",
        "illustrative" => true,
        "score" => 0.70,
        "findings" => [
          %{
            "code" => "residual_motion",
            "message" => "Residual response remains.",
            "severity" => "warning",
            "artifact" => "interaction.json",
            "fragment" => "final"
          }
        ]
      }
    }
  end

  defp artifact(name) do
    %Artifact{
      id: "id-#{name}",
      name: name,
      kind: :other,
      path: "artifacts/#{name}",
      sha256: String.duplicate("0", 64),
      media_type: "application/octet-stream",
      produced_by: %{}
    }
  end

  defp write_artifact(root, name, value) do
    File.write!(Path.join(root, name), JSON.encode!(value))
    artifact_entry(name)
  end

  defp artifact_entry(name) do
    %{"id" => "id-#{name}", "name" => name, "path" => "artifacts/#{name}"}
  end

  defp episode do
    %Episode{
      capsule_id: "capsule",
      episode_id: "episode",
      capsule_version: "capsule@1",
      task_version: "task@1",
      fixture_digest: "fixture",
      verifier_version: Verifier.version(),
      verifier_digest: Verifier.digest(),
      runtime: %RuntimeFingerprint{}
    }
  end

  defp trace(episode, artifacts) do
    %Trace{
      capsule_id: episode.capsule_id,
      episode_id: episode.episode_id,
      task_version: episode.task_version,
      verifier_version: episode.verifier_version,
      seed: 1,
      episode: episode,
      artifacts: artifacts
    }
  end
end
