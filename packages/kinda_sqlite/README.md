# Kinda SQLite

`kinda_sqlite` is a low-level SQLite driver built with Kinda. It binds the
pinned SQLite 3.53.4 amalgamation and is organized as an independent OTP
application that can grow into the native driver beneath a DBConnection and
Ecto SQL adapter.

The boundary is intentional:

- `Kinda.SQLite` is the public driver API.
- `Kinda.SQLite.Native` is the private NIF boundary.
- `native/` owns SQLite handles and their resource lifetimes.
- `vendor/sqlite/` contains the pinned upstream SQLite source.
- `test/kinda/sqlite/` covers queries, ownership, GC order, NIF isolation, and
  hot upgrades.

An eventual Ecto integration should live in a separate `ecto_kinda_sqlite`
package under `Ecto.Adapters.KindaSQLite`. That package can implement the
DBConnection and Ecto SQL contracts while keeping this driver independently
usable and testable.

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
