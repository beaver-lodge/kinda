defmodule Kinda.DuckDBTest do
  use ExUnit.Case, async: true

  alias Kinda.DuckDB

  test "loads the pinned DuckDB runtime" do
    assert DuckDB.library_version() == "v1.5.5"
  end

  test "executes an integer scalar through the DuckDB C API" do
    assert DuckDB.query_int64("select 40 + 2") == 42
  end

  @tag :tmp_dir
  test "opens a file database", %{tmp_dir: tmp_dir} do
    database = Path.join(tmp_dir, "bootstrap.duckdb")

    assert DuckDB.query_int64("select 7 * 6", database) == 42
    assert File.exists?(database)
  end
end
