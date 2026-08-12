# Ecto Kinda DuckDB

`ecto_kinda_duckdb` is an experimental Ecto SQL adapter backed entirely by
`kinda_duckdb` for database I/O. It is intended for analytical reads and
transaction-scoped DuckDB work, not as a drop-in OLTP adapter.

Supported now:

- `Repo.query/3` and `Repo.query!/3`
- Ecto `SELECT` queries using PostgreSQL-style SQL generation
- `Repo.stream/2` inside a transaction
- top-level commit and rollback
- DBConnection pooling, prepared queries, timeout interruption, and reconnect

Explicitly not promised:

- schema insert, update, or delete callbacks
- `update_all` or `delete_all`
- Ecto migrations or migration locking
- nested transactions/savepoints
- constraint translation
- complete PostgreSQL type, DDL, locking, or OLTP semantics

The current scalar result surface covers nulls, booleans, signed 64-bit
integers, doubles, and strings. DuckDB expressions that produce wider or
complex types should be cast explicitly to a supported result type.

```elixir
defmodule MyApp.AnalyticsRepo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.KindaDuckDB
end

config :my_app, MyApp.AnalyticsRepo,
  database: "analytics.duckdb",
  pool_size: 2
```

The PostgreSQL dependency supplies Ecto's maintained read-query SQL generator;
it does not open PostgreSQL connections. Every query executes through
`Kinda.DuckDB.DBConnection` and the DuckDB C API.
