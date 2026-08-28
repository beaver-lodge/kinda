defmodule Kinda.Capsule.Web3D.EventIndexTest do
  use ExUnit.Case, async: true

  alias Kinda.Capsule.{Episode, RuntimeFingerprint, Score, Trace}
  alias Kinda.Capsule.Web3D.EventIndex
  alias Kinda.SQLite.Connection

  @tag :tmp_dir
  test "indexes episode identity and its domain events", %{tmp_dir: tmp_dir} do
    database = Path.join(tmp_dir, "episodes.sqlite3")
    trace = trace()

    assert :ok = EventIndex.record(database, trace, "bundle-digest")
    {:ok, connection} = Connection.start_link(database: database)

    assert %{rows: [["episode", "bundle-digest", 0.83]]} =
             Connection.query!(
               connection,
               "SELECT episode_id, bundle_digest, score FROM episodes"
             )

    assert %{rows: [["reset"], ["sealed"]]} =
             Connection.query!(
               connection,
               "SELECT kind FROM episode_events ORDER BY sequence"
             )

    GenServer.stop(connection)
  end

  defp trace do
    episode = %Episode{
      capsule_id: "capsule",
      episode_id: "episode",
      capsule_version: "capsule@1",
      task_version: "task@1",
      fixture_digest: "fixture-digest",
      verifier_version: "verifier@1",
      verifier_digest: "verifier-digest",
      runtime: %RuntimeFingerprint{}
    }

    %Trace{
      capsule_id: episode.capsule_id,
      episode_id: episode.episode_id,
      task_version: episode.task_version,
      verifier_version: episode.verifier_version,
      seed: "showcase",
      episode: episode,
      score: %Score{value: 0.83}
    }
  end
end
