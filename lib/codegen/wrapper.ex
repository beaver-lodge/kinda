defmodule Kinda.CodeGen.Wrapper do
  require Logger
  @moduledoc false
  defstruct types: [], functions: [], root_module: nil

  # Generate Zig code from a header and build a Zig project to produce a NIF library
  def gen_and_build_zig(opts) do
    wrapper = Keyword.fetch!(opts, :wrapper)
    lib_name = Keyword.fetch!(opts, :lib_name)
    dest_dir = Keyword.fetch!(opts, :dest_dir)
    version = Keyword.fetch!(opts, :version)

    Logger.debug("[Kinda] generating Elixir code for wrapper: #{wrapper}")

    {:ok, target} = RustlerPrecompiled.target()
    lib_name = "#{lib_name}-v#{version}-#{target}"

    # zig will add the 'lib' prefix to the library name
    prefixed_lib_name = "lib#{lib_name}"

    %{dest_dir: dest_dir, lib_name: prefixed_lib_name}
  end
end
