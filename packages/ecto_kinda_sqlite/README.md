# Ecto Kinda SQLite

`ecto_kinda_sqlite` is the Ecto SQL adapter for `kinda_sqlite`. Repository
queries, schemas, migrations, transactions, streaming, constraints, and SQL
Sandbox all execute through `Kinda.SQLite.Connection`.

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.KindaSQLite
end
```

Configure a file database for normal applications:

```elixir
config :my_app, MyApp.Repo,
  database: Path.expand("../my_app.sqlite3", __DIR__),
  pool_size: 5
```

Use `pool_size: 1` when the database is `:memory:` or `":memory:"`.
