Application.put_env(:ecto_kinda_duckdb, EctoKindaDuckDB.TestRepo,
  database: :memory,
  pool_size: 1,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true
)

{:ok, _pid} = EctoKindaDuckDB.TestRepo.start_link()

ExUnit.start()
