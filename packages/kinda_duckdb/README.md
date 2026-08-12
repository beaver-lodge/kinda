# Kinda DuckDB

`kinda_duckdb` binds the official DuckDB C API through Kinda. The package pins
DuckDB v1.5.5 and verifies the release archive before any header or shared
library reaches the native build.

The bootstrap supports the repository's five native targets:

- Linux x86_64 and aarch64
- macOS x86_64 and aarch64 through DuckDB's universal archive
- Windows x86_64

The initial API proves the packaged runtime and C ABI with scalar queries:

```elixir
Kinda.DuckDB.library_version()
Kinda.DuckDB.query_int64("select 40 + 2")
```

Later layers add resource-backed connections, columnar results, Appender,
pending queries, and DBConnection without changing the pinned runtime supply
chain established here.
