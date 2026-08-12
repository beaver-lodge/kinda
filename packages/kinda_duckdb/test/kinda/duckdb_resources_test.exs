defmodule Kinda.DuckDBResourcesTest do
  use ExUnit.Case, async: false

  alias Kinda.DuckDB
  alias Kinda.DuckDB.{BorrowedResult, Result}
  alias Kinda.DuckDB.Native

  setup do
    database = DuckDB.open()
    connection = DuckDB.connect(database)
    on_exit(fn -> DuckDB.close(connection) end)
    on_exit(fn -> DuckDB.close(database) end)
    %{connection: connection, database: database}
  end

  test "materializes safe BEAM-owned columnar results", %{connection: connection} do
    assert %Result{
             columns: [
               %{name: "id", values: [1, 2]},
               %{name: "name", values: ["one", "two"]},
               %{name: "active", values: [true, false]},
               %{name: "score", values: [1.5, 2.5]},
               %{name: "missing", values: [nil, nil]}
             ],
             row_count: 2
           } =
             DuckDB.query(
               connection,
               """
               select *
               from (values
                 (1::bigint, 'one', true, 1.5::double, null),
                 (2::bigint, 'two', false, 2.5::double, null)
               ) values_table(id, name, active, score, missing)
               """
             )
  end

  test "borrowed results survive arbitrary parent close order", %{
    connection: connection,
    database: database
  } do
    assert %BorrowedResult{} = borrowed = DuckDB.query_borrowed(connection, "select 42 as answer")

    :ok = DuckDB.close(database)
    :ok = DuckDB.close(connection)

    assert %Result{columns: [%{name: "answer", values: [42]}]} =
             DuckDB.materialize(borrowed)

    :ok = DuckDB.close(borrowed)
    :ok = DuckDB.close(borrowed)
  end

  test "Appender retains its connection and bulk appends typed rows", %{
    connection: connection,
    database: database
  } do
    DuckDB.query(
      connection,
      "create table metrics(id bigint, name varchar, active boolean, score double)"
    )

    appender = DuckDB.create_appender(connection, "metrics")
    :ok = DuckDB.append(appender, [1, "one", true, 1.5])
    :ok = DuckDB.append(appender, [2, "two", false, nil])
    :ok = DuckDB.flush(appender)

    assert %Result{
             columns: [
               %{name: "id", values: [1, 2]},
               %{name: "name", values: ["one", "two"]},
               %{name: "active", values: [true, false]},
               %{name: "score", values: [1.5, nil]}
             ]
           } = DuckDB.query(connection, "select * from metrics order by id")

    :ok = DuckDB.close(database)
    :ok = DuckDB.close(connection)
    :ok = DuckDB.close(appender)
    :ok = DuckDB.close(appender)
  end

  test "resources remain isolated from SQLite NIF resources", %{connection: connection} do
    sqlite = Kinda.SQLite.open_memory() |> elem(1)
    assert %{columns: [%{values: [42]}]} = DuckDB.query(connection, "select 42")
    assert {:ok, %{rows: [[42]]}} = Kinda.SQLite.query(sqlite, "select 42")
    assert %Kinda.CallError{} = catch_error(Native.query(sqlite.resource, "select 42"))
    :ok = Kinda.SQLite.close(sqlite)
  end

  test "resources survive parent wrapper garbage collection", %{connection: connection} do
    borrowed = DuckDB.query_borrowed(connection, "select 7 as value")
    connection = nil
    _database = nil
    :erlang.garbage_collect(self())

    assert connection == nil
    assert %{columns: [%{values: [7]}]} = DuckDB.materialize(borrowed)
  end

  @tag :tmp_dir
  test "borrowed resources survive a NIF hot upgrade", %{
    connection: connection,
    tmp_dir: tmp_dir
  } do
    borrowed = DuckDB.query_borrowed(connection, "select 42 as answer")
    upgrade = copy_nif!(tmp_dir)
    original = remember_module(Native)

    on_exit(fn -> restore_module(original) end)

    assert {:module, Native, _binary, _result} = hot_upgrade_module(Native, upgrade)
    :code.purge(Native)

    assert %{columns: [%{name: "answer", values: [42]}]} = DuckDB.materialize(borrowed)
  end

  defp copy_nif!(tmp_dir) do
    base = "#{:code.priv_dir(:kinda_duckdb)}/lib/libKindaDuckDBNIF"

    source =
      Enum.find_value([".so", ".dylib", ".dll"], fn extension ->
        path = base <> extension
        if File.exists?(path), do: path
      end) || raise "could not find Kinda DuckDB NIF"

    destination = Path.join(tmp_dir, "libKindaDuckDBNIFUpgrade")
    File.cp!(source, destination <> Path.extname(source))
    destination
  end

  defp remember_module(module) do
    {^module, binary, path} = :code.get_object_code(module)
    {module, binary, path}
  end

  defp restore_module({module, binary, path}) do
    assert {:module, ^module} = :code.load_binary(module, path, binary)
    :code.purge(module)
  end

  defp hot_upgrade_module(module, nif_file) do
    stubs =
      for {name, arity} <- module.__info__(:functions), name != :load_nif do
        args = Macro.generate_arguments(arity, __MODULE__)

        quote do
          def unquote(name)(unquote_splicing(args)),
            do: :erlang.nif_error({:nif_not_loaded, unquote(name)})
        end
      end

    body =
      quote do
        @on_load :load_nif

        def load_nif do
          :erlang.load_nif(unquote(String.to_charlist(nif_file)), 0)
        end

        unquote_splicing(stubs)
      end

    compiler_options = Code.compiler_options()
    Code.compiler_options(ignore_module_conflict: true)

    try do
      Module.create(module, body, Macro.Env.location(__ENV__))
    after
      Code.compiler_options(compiler_options)
    end
  end
end
