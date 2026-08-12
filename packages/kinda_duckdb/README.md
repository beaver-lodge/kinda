# Kinda DuckDB

`kinda_duckdb` binds the official DuckDB C API through Kinda. The package pins
DuckDB v1.5.5 and verifies the release archive before any header or shared
library reaches the native build.

The bootstrap supports the repository's five native targets:

- Linux x86_64 and aarch64
- macOS x86_64 and aarch64 through DuckDB's universal archive
- Windows x86_64

The driver exposes explicit database, connection, borrowed-result, and
Appender resources. Parent resources are retained natively and explicit close
requests are deferred until their children finish, so arbitrary close and GC
orders are safe.

Queries materialize BEAM-owned columnar data by default:

```elixir
database = Kinda.DuckDB.open()
connection = Kinda.DuckDB.connect(database)
result = Kinda.DuckDB.query(connection, "select 40 + 2 as answer")
```

Use `query_borrowed/2` for an explicitly resource-backed result and
`create_appender/2` with `append/2` for typed bulk insertion. Later layers add
pending queries and DBConnection without changing this ownership graph or the
pinned runtime supply chain.
