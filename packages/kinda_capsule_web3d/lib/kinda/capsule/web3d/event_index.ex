defmodule Kinda.Capsule.Web3D.EventIndex do
  @moduledoc "SQLite projection of addressable episode events and evidence."

  alias Kinda.Capsule.Trace
  alias Kinda.SQLite.Connection

  @spec record(binary(), Trace.t(), binary()) :: :ok | {:error, term()}
  def record(database, %Trace{} = trace, bundle_digest) do
    with {:ok, connection} <- Connection.start_link(database: database) do
      try do
        DBConnection.transaction(connection, fn connection ->
          bootstrap(connection)
          insert_episode(connection, trace, bundle_digest)

          trace
          |> events(bundle_digest)
          |> Enum.with_index()
          |> Enum.each(fn {event, sequence} ->
            insert_event(connection, trace, sequence, event)
          end)
        end)
        |> case do
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
        end
      after
        GenServer.stop(connection)
      end
    end
  end

  defp bootstrap(connection) do
    query!(
      connection,
      """
      CREATE TABLE IF NOT EXISTS episodes (
        episode_id TEXT PRIMARY KEY,
        capsule_id TEXT NOT NULL,
        task_version TEXT NOT NULL,
        verifier_version TEXT NOT NULL,
        fixture_digest TEXT NOT NULL,
        bundle_digest TEXT NOT NULL,
        score REAL,
        recorded_at_ms INTEGER NOT NULL
      )
      """
    )

    query!(
      connection,
      """
      CREATE TABLE IF NOT EXISTS episode_events (
        episode_id TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        kind TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        evidence_artifact_id TEXT,
        PRIMARY KEY (episode_id, sequence),
        FOREIGN KEY (episode_id) REFERENCES episodes(episode_id)
      )
      """
    )
  end

  defp insert_episode(connection, trace, bundle_digest) do
    query!(
      connection,
      """
      INSERT INTO episodes
        (episode_id, capsule_id, task_version, verifier_version, fixture_digest,
         bundle_digest, score, recorded_at_ms)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        trace.episode_id,
        trace.capsule_id,
        trace.task_version,
        trace.verifier_version,
        trace.episode.fixture_digest,
        bundle_digest,
        trace.score && trace.score.value,
        System.system_time(:millisecond)
      ]
    )
  end

  defp events(trace, bundle_digest) do
    reset = [%{kind: "reset", payload: %{seed: inspect(trace.seed)}, evidence: nil}]

    steps =
      Enum.map(trace.steps, fn step ->
        %{
          kind: "command",
          payload: %{
            sequence: step.sequence,
            executable: step.action.executable,
            args: step.action.args,
            termination: inspect(step.termination),
            duration: step.duration,
            metadata: step.metadata
          },
          evidence: nil
        }
      end)

    artifacts =
      Enum.map(trace.artifacts, fn artifact ->
        %{
          kind: "artifact",
          payload: %{name: artifact.name, kind: artifact.kind, sha256: artifact.sha256},
          evidence: artifact.id
        }
      end)

    sealed = [
      %{
        kind: "sealed",
        payload: %{bundle_digest: bundle_digest, score: trace.score && trace.score.value},
        evidence: nil
      }
    ]

    reset ++ steps ++ artifacts ++ sealed
  end

  defp insert_event(connection, trace, sequence, event) do
    query!(
      connection,
      """
      INSERT INTO episode_events
        (episode_id, sequence, kind, payload_json, evidence_artifact_id)
      VALUES (?, ?, ?, ?, ?)
      """,
      [trace.episode_id, sequence, event.kind, JSON.encode!(event.payload), event.evidence]
    )
  end

  defp query!(connection, statement, parameters \\ []) do
    Connection.query!(connection, statement, parameters)
  end
end
