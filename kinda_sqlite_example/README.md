# Kinda SQLite Example

This independent OTP application binds the SQLite 3.53.4 C API with a second
Kinda NIF library. It exercises behavior that a scalar example cannot cover:

- real `sqlite3` and `sqlite3_stmt` native handles
- retained parent ownership from statements to database connections
- parent-first and child-first garbage collection
- resource-type isolation between two simultaneously loaded Kinda NIFs
- hot upgrades while resources from both NIF libraries remain live

SQLite is built as a companion shared library from the pinned amalgamation.
Keeping the SQLite runtime outside the versioned NIF library allows old and new
NIF generations to operate on the same live handles during hot upgrade.

From the repository root:

```sh
mix kinda.sqlite.example.verify
```

Or directly:

```sh
cd kinda_sqlite_example
mix deps.get
mix test --force
```
