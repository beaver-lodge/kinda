database = Path.expand("tmp/ecto_kinda_sqlite_test.sqlite3", __DIR__ <> "/..")
File.mkdir_p!(Path.dirname(database))
File.rm(database)
File.rm(database <> "-shm")
File.rm(database <> "-wal")

Application.put_env(:ecto_kinda_sqlite, EctoKindaSQLite.TestRepo,
  database: database,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 2,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true
)

{:ok, _pid} = EctoKindaSQLite.TestRepo.start_link()
:ok = Ecto.Migrator.up(EctoKindaSQLite.TestRepo, 1, EctoKindaSQLite.Migration, log: false)
:ok = Ecto.Adapters.SQL.Sandbox.mode(EctoKindaSQLite.TestRepo, :manual)

ExUnit.start()
