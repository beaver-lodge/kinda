defmodule Kinda.Capsule.Web3D.VerifierTest do
  use ExUnit.Case, async: true

  alias Kinda.Capsule.{Artifact, Episode, Observation, RuntimeFingerprint, Trace, Verification}
  alias Kinda.Capsule.Web3D.Verifier

  test "gates scoring dimensions and binds judgments to evidence" do
    artifacts = [
      artifact("interaction.json"),
      artifact("interaction.webm"),
      artifact("performance.json"),
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
    failed = put_in(result(), ["gates", "build_and_load"], false)

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

  defp result do
    %{
      "gates" => %{
        "fixture_integrity" => true,
        "verifier_integrity" => true,
        "build_and_load" => true,
        "critical_interaction" => true
      },
      "scores" => %{"interaction" => 0.88, "performance" => 0.91, "expert" => 0.70},
      "failure_modes" => [
        %{
          "code" => "residual_motion",
          "message" => "Residual response remains.",
          "severity" => "warning",
          "artifact" => "interaction.json",
          "fragment" => "final"
        }
      ]
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
