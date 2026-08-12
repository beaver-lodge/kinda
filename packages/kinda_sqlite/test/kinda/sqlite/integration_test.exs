defmodule Kinda.SQLite.IntegrationTest do
  use ExUnit.Case, async: false

  alias Kinda.SQLite
  alias Kinda.SQLite.Native, as: SqliteRaw
  alias KindaExample.NIF.Raw, as: ExampleRaw

  test "executes a real prepared SQLite query with typed bindings" do
    database = SQLite.open_memory()
    assert SQLite.sqlite_version() == "3.53.4"
    assert :ok = SQLite.execute(database, "create table people(id integer, name text)")

    insert = SQLite.prepare(database, "insert into people values (?, ?)")
    assert :ok = SQLite.bind_int64(insert, 1, 42)
    assert :ok = SQLite.bind_text(insert, 2, "Ada")
    assert :done = SQLite.step(insert)
    assert 1 = SQLite.database_changes(database)

    query = SQLite.prepare(database, "select id, name from people")
    assert :row = SQLite.step(query)
    assert 42 = SQLite.column_int64(query, 0)
    assert "Ada" = SQLite.column_text(query, 1)
    assert :done = SQLite.step(query)
  end

  test "a statement retains its database when the parent term is collected first" do
    baseline = SqliteRaw.lifecycle_stats()
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        statement = prepare_statement_without_database_term()
        :erlang.garbage_collect()
        send(parent, {:parent_term_collected, self()})

        receive do
          :step ->
            send(parent, {:row, SqliteRaw.step(statement), SqliteRaw.column_int64(statement, 0)})
        end

        receive do
          :release -> :ok
        end
      end)

    assert_receive {:parent_term_collected, ^owner}
    assert lifecycle_delta(SqliteRaw.lifecycle_stats(), baseline) == {1, 0, 1, 0}

    send(owner, :step)
    assert_receive {:row, :row, 7}
    send(owner, :release)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}

    assert_eventually(fn ->
      lifecycle_reached?(SqliteRaw.lifecycle_stats(), baseline, {1, 1, 1, 1})
    end)
  end

  test "the database remains usable when a child statement is collected first" do
    baseline = SqliteRaw.lifecycle_stats()
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        database = SqliteRaw.open_memory()
        assert :ok = SqliteRaw.execute(database, "create table events(id integer)")
        create_and_drop_statement(database)
        :erlang.garbage_collect()
        send(parent, {:child_term_collected, self()})

        receive do
          :use_database ->
            send(
              parent,
              {:database_result, SqliteRaw.execute(database, "insert into events values (1)")}
            )
        end

        receive do
          :release -> :ok
        end
      end)

    assert_receive {:child_term_collected, ^owner}

    assert_eventually(fn ->
      lifecycle_reached?(SqliteRaw.lifecycle_stats(), baseline, {1, 0, 1, 1})
    end)

    send(owner, :use_database)
    assert_receive {:database_result, :ok}
    send(owner, :release)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}

    assert_eventually(fn ->
      lifecycle_reached?(SqliteRaw.lifecycle_stats(), baseline, {1, 1, 1, 1})
    end)
  end

  test "resource types with identical native names stay isolated across NIF libraries" do
    sqlite_scalar = SqliteRaw.scalar_make(11)
    example_scalar = ExampleRaw."Elixir.KindaExample.NIF.CInt.make"(22)
    database = SqliteRaw.open_memory()

    assert 11 = SqliteRaw.scalar_value(sqlite_scalar)
    assert 22 = ExampleRaw."Elixir.KindaExample.NIF.CInt.primitive"(example_scalar)

    assert %Kinda.CallError{} = catch_error(SqliteRaw.scalar_value(example_scalar))

    assert %Kinda.CallError{} =
             catch_error(ExampleRaw."Elixir.KindaExample.NIF.CInt.primitive"(sqlite_scalar))

    assert %Kinda.CallError{} =
             catch_error(ExampleRaw."Elixir.KindaExample.NIF.CInt.primitive"(database))
  end

  @tag :tmp_dir
  test "both NIF libraries coexist while each is hot-upgraded", %{tmp_dir: tmp_dir} do
    if match?({:win32, _}, :os.type()) do
      verify_windows_hot_upgrade(tmp_dir)
    else
      verify_live_resource_hot_upgrade(tmp_dir)
    end
  end

  defp verify_live_resource_hot_upgrade(tmp_dir) do
    database = SqliteRaw.open_memory()
    assert :ok = SqliteRaw.execute(database, "create table values_table(value integer)")
    assert :ok = SqliteRaw.execute(database, "insert into values_table values (99)")
    statement = SqliteRaw.prepare(database, "select value from values_table")
    example_scalar = ExampleRaw."Elixir.KindaExample.NIF.CInt.make"(33)

    sqlite_upgrade = copy_nif!(:kinda_sqlite, "KindaSQLiteNIF", tmp_dir)
    example_upgrade = copy_nif!(:kinda_example, "KindaExampleNIF", tmp_dir)

    originals = [remember_module(SqliteRaw), remember_module(ExampleRaw)]

    on_exit(fn ->
      Enum.each(originals, &restore_module/1)
    end)

    assert {:module, SqliteRaw, _binary, _result} =
             hot_upgrade_module(SqliteRaw, sqlite_upgrade)

    :code.purge(SqliteRaw)
    assert :row = SqliteRaw.step(statement)
    assert 99 = SqliteRaw.column_int64(statement, 0)
    assert 33 = ExampleRaw."Elixir.KindaExample.NIF.CInt.primitive"(example_scalar)

    assert {:module, ExampleRaw, _binary, _result} =
             hot_upgrade_module(ExampleRaw, example_upgrade)

    :code.purge(ExampleRaw)
    assert :ok = SqliteRaw.execute(database, "insert into values_table values (100)")
    assert 33 = ExampleRaw."Elixir.KindaExample.NIF.CInt.primitive"(example_scalar)
  end

  defp verify_windows_hot_upgrade(tmp_dir) do
    example_scalar = ExampleRaw."Elixir.KindaExample.NIF.CInt.make"(33)
    assert_sqlite_query(99)
    :erlang.garbage_collect()

    sqlite_upgrade = copy_nif!(:kinda_sqlite, "KindaSQLiteNIF", tmp_dir)
    example_upgrade = copy_nif!(:kinda_example, "KindaExampleNIF", tmp_dir)
    originals = [remember_module(SqliteRaw), remember_module(ExampleRaw)]

    on_exit(fn ->
      Enum.each(originals, &restore_module/1)
    end)

    assert {:module, SqliteRaw, _binary, _result} =
             hot_upgrade_module(SqliteRaw, sqlite_upgrade)

    :code.purge(SqliteRaw)
    assert_sqlite_query(100)
    assert 33 = ExampleRaw."Elixir.KindaExample.NIF.CInt.primitive"(example_scalar)

    assert {:module, ExampleRaw, _binary, _result} =
             hot_upgrade_module(ExampleRaw, example_upgrade)

    :code.purge(ExampleRaw)
    assert_sqlite_query(101)
    assert 33 = ExampleRaw."Elixir.KindaExample.NIF.CInt.primitive"(example_scalar)
  end

  defp assert_sqlite_query(value) do
    database = SqliteRaw.open_memory()
    assert :ok = SqliteRaw.execute(database, "create table values_table(value integer)")
    assert :ok = SqliteRaw.execute(database, "insert into values_table values (#{value})")
    statement = SqliteRaw.prepare(database, "select value from values_table")
    assert :row = SqliteRaw.step(statement)
    assert ^value = SqliteRaw.column_int64(statement, 0)
  end

  defp prepare_statement_without_database_term do
    database = SqliteRaw.open_memory()
    assert :ok = SqliteRaw.execute(database, "create table retained(value integer)")
    assert :ok = SqliteRaw.execute(database, "insert into retained values (7)")
    SqliteRaw.prepare(database, "select value from retained")
  end

  defp create_and_drop_statement(database) do
    statement = SqliteRaw.prepare(database, "select count(*) from events")
    assert :row = SqliteRaw.step(statement)
    :ok
  end

  defp lifecycle_delta(counts, baseline) do
    counts
    |> Tuple.to_list()
    |> Enum.zip_with(Tuple.to_list(baseline), &Kernel.-/2)
    |> List.to_tuple()
  end

  defp lifecycle_reached?(counts, baseline, increments) do
    counts
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(baseline))
    |> Enum.zip(Tuple.to_list(increments))
    |> Enum.all?(fn {{count, initial}, increment} -> count >= initial + increment end)
  end

  defp assert_eventually(assertion, attempts \\ 100)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      :ok
    else
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(assertion, 0), do: assert(assertion.())

  defp copy_nif!(application, library, tmp_dir) do
    base = "#{:code.priv_dir(application)}/lib/lib#{library}"

    source =
      Enum.find_value([".so", ".dylib", ".dll"], fn extension ->
        path = base <> extension
        if File.exists?(path), do: path
      end) || raise "could not find #{library} NIF"

    destination = Path.join(tmp_dir, "lib#{library}Upgrade")
    File.cp!(source, destination <> Path.extname(source))
    destination
  end

  defp remember_module(module) do
    {module, binary, path} = :code.get_object_code(module)
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
