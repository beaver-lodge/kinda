defmodule Kinda.SQLite.IntegrationTest do
  use ExUnit.Case, async: true

  alias Kinda.SQLite
  alias Kinda.SQLite.Blob
  alias Kinda.SQLite.Native, as: SqliteRaw
  alias Kinda.Testing.{Isolated, NativeScenario}
  alias KindaExample.NIF.Raw, as: ExampleRaw

  test "executes a real prepared SQLite query with typed bindings" do
    assert {:ok, database} = SQLite.open_memory()
    assert SQLite.sqlite_version() == "3.53.4"

    assert {:ok, %{num_rows: 0}} =
             SQLite.query(database, "create table people(id integer, name text)")

    assert {:ok, %{num_rows: 1}} =
             SQLite.query(database, "insert into people values (?, ?)", [42, "Ada"])

    assert {:ok, %{columns: ["id", "name"], rows: [[42, "Ada"]], num_rows: 1}} =
             SQLite.query(database, "select id, name from people")
  end

  test "round-trips all scalar classes and reports structured errors" do
    assert {:ok, database} = SQLite.open_memory()

    assert {:ok, %{rows: [[nil, 7, 1.5, "text", %Blob{data: <<0, 1, 2>>}]]}} =
             SQLite.query(database, "select ?, ?, ?, ?, ?", [
               nil,
               7,
               1.5,
               "text",
               %Blob{data: <<0, 1, 2>>}
             ])

    assert {:error, %Kinda.SQLite.Error{operation: :prepare, code: code, sql: "not sql"}} =
             SQLite.query(database, "not sql")

    assert is_integer(code)
    assert :ok = SQLite.close(database)
    assert :ok = SQLite.close(database)
  end

  test "a statement retains its database when the parent term is collected first" do
    steps = [
      {:call, :database, {SqliteRaw, :open_memory, []}},
      {:expect, :ok,
       {SqliteRaw, :execute, [{:resource, :database}, "create table retained(value integer)"]}},
      {:expect, :ok,
       {SqliteRaw, :execute, [{:resource, :database}, "insert into retained values (7)"]}},
      {:call, :statement,
       {SqliteRaw, :prepare, [{:resource, :database}, "select value from retained"]}},
      {:drop, :database},
      :garbage_collect,
      {:eventually_expect, {1, 0, 1, 0}, {SqliteRaw, :lifecycle_stats, []}},
      {:expect, :row, {SqliteRaw, :step, [{:resource, :statement}]}},
      {:expect, 7, {SqliteRaw, :column_int64, [{:resource, :statement}, 0]}},
      {:drop, :statement},
      :garbage_collect,
      {:eventually_expect, {1, 1, 1, 1}, {SqliteRaw, :lifecycle_stats, []}}
    ]

    assert Isolated.run({NativeScenario, :run, [steps]}) == :ok
  end

  test "the database remains usable when a child statement is collected first" do
    steps = [
      {:call, :database, {SqliteRaw, :open_memory, []}},
      {:expect, :ok,
       {SqliteRaw, :execute, [{:resource, :database}, "create table events(id integer)"]}},
      {:call, :statement,
       {SqliteRaw, :prepare, [{:resource, :database}, "select count(*) from events"]}},
      {:expect, :row, {SqliteRaw, :step, [{:resource, :statement}]}},
      {:drop, :statement},
      :garbage_collect,
      {:eventually_expect, {1, 0, 1, 1}, {SqliteRaw, :lifecycle_stats, []}},
      {:expect, :ok,
       {SqliteRaw, :execute, [{:resource, :database}, "insert into events values (1)"]}},
      {:drop, :database},
      :garbage_collect,
      {:eventually_expect, {1, 1, 1, 1}, {SqliteRaw, :lifecycle_stats, []}}
    ]

    assert Isolated.run({NativeScenario, :run, [steps]}) == :ok
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
      steps = [
        {:call, :database, {SqliteRaw, :open_memory, []}},
        {:expect, :ok,
         {SqliteRaw, :execute,
          [{:resource, :database}, "create table values_table(value integer)"]}},
        {:expect, :ok,
         {SqliteRaw, :execute, [{:resource, :database}, "insert into values_table values (99)"]}},
        {:call, :statement,
         {SqliteRaw, :prepare, [{:resource, :database}, "select value from values_table"]}},
        {:call, :example_scalar, {ExampleRaw, :"Elixir.KindaExample.NIF.CInt.make", [33]}},
        {:upgrade, SqliteRaw, :kinda_sqlite, "KindaSQLiteNIF"},
        {:purge, SqliteRaw},
        {:expect, :row, {SqliteRaw, :step, [{:resource, :statement}]}},
        {:expect, 99, {SqliteRaw, :column_int64, [{:resource, :statement}, 0]}},
        {:expect, 33,
         {ExampleRaw, :"Elixir.KindaExample.NIF.CInt.primitive", [{:resource, :example_scalar}]}},
        {:upgrade, ExampleRaw, :kinda_example, "KindaExampleNIF"},
        {:purge, ExampleRaw},
        {:expect, :ok,
         {SqliteRaw, :execute, [{:resource, :database}, "insert into values_table values (100)"]}},
        {:expect, 33,
         {ExampleRaw, :"Elixir.KindaExample.NIF.CInt.primitive", [{:resource, :example_scalar}]}}
      ]

      assert Isolated.run({NativeScenario, :run, [steps]}, timeout: 120_000) == :ok
    end
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
