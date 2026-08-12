defmodule Kinda.DuckDB do
  @moduledoc """
  Minimal DuckDB C API surface backed by the pinned official runtime.

  Resource-backed connections and columnar results are introduced in the next
  driver layer. These scalar calls establish the runtime supply chain and ABI.
  """

  alias Kinda.DuckDB.Native

  @spec library_version() :: String.t()
  def library_version, do: Native.library_version()

  @spec query_int64(iodata(), Path.t()) :: integer()
  def query_int64(sql, database \\ ":memory:") do
    Native.query_int64(IO.iodata_to_binary(database), IO.iodata_to_binary(sql))
  end
end
