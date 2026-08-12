# Kinda SQLite

`kinda_sqlite` is a low-level SQLite driver built with Kinda. It binds the
pinned SQLite 3.53.4 amalgamation and is organized as an independent OTP
application with a `DBConnection` implementation suitable for an Ecto SQL
adapter.

The boundary is intentional:

- `Kinda.SQLite` is the public driver API.
- `Kinda.SQLite.Connection` provides pooling, prepared queries, transactions,
  and incremental streams through `DBConnection`.
- `Kinda.SQLite.Native` is the private NIF boundary.
- `native/` owns SQLite handles and their resource lifetimes.
- `vendor/sqlite/` contains the pinned upstream SQLite source.
- `test/kinda/sqlite/` covers queries, ownership, GC order, NIF isolation, and
  hot upgrades.

The Ecto integration lives separately in `ecto_kinda_sqlite` under
`Ecto.Adapters.KindaSQLite`, keeping this driver independently usable and
testable.

Start a connection and run a parameterized query:

```elixir
{:ok, connection} = Kinda.SQLite.Connection.start_link(database: "example.sqlite3")

Kinda.SQLite.Connection.query!(
  connection,
  "select name from users where id = ?",
  [42]
)
```

Each pool worker owns one SQLite connection. Use `pool_size: 1` with the
default `:memory:` database because separate in-memory connections do not share
state; file databases can use larger pools.

SQLite is built as a companion shared library. Keeping its runtime outside the
versioned NIF library allows old and new NIF generations to operate on the same
live handles during hot upgrades.

From the repository root:

```sh
mix kinda.sqlite.verify
```

Or directly:

```sh
cd packages/kinda_sqlite
mix deps.get
mix test --force
```
