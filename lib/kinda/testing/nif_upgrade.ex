defmodule Kinda.Testing.NIFUpgrade do
  @moduledoc """
  Test support for loading a second copy of a NIF into an existing module.

  The copied library keeps the same native entry name; the distinct path only
  gives the dynamic loader a second image to pass through the NIF `upgrade`
  callback. Use the separate `kinda_sandbox` package when the entry name itself
  must differ.
  """

  defmodule Snapshot do
    @moduledoc false
    @enforce_keys [:module, :binary, :path]
    defstruct [:module, :binary, :path]
  end

  @type snapshot :: %Snapshot{module: module(), binary: binary(), path: charlist()}

  @spec copy_library!(atom(), String.t(), Path.t(), keyword()) :: Path.t()
  def copy_library!(application, library, directory, options \\ []) do
    suffix = Keyword.get(options, :suffix, "Upgrade")
    base = Path.join([to_string(:code.priv_dir(application)), "lib", "lib#{library}"])

    source =
      Enum.find_value([".so", ".dylib", ".dll"], fn extension ->
        path = base <> extension
        if File.exists?(path), do: path
      end) || raise "could not find #{library} NIF for #{application}"

    destination = Path.join(directory, "lib#{library}#{suffix}")
    File.cp!(source, destination <> Path.extname(source))
    destination
  end

  @spec remember!(module()) :: snapshot()
  def remember!(module) do
    case :code.get_object_code(module) do
      {^module, binary, path} -> %Snapshot{module: module, binary: binary, path: path}
      :error -> raise "could not read object code for #{inspect(module)}"
    end
  end

  @spec restore!(snapshot()) :: :ok
  def restore!(%Snapshot{module: module, binary: binary, path: path}) do
    {:module, ^module} = :code.load_binary(module, path, binary)
    :code.purge(module)
    :ok
  end

  @spec load!(module(), Path.t()) :: {:module, module(), binary(), term()}
  def load!(module, nif_file) do
    body = module_body(module, nif_file)
    compiler_options = Code.compiler_options()
    Code.compiler_options(ignore_module_conflict: true)

    try do
      Module.create(module, body, Macro.Env.location(__ENV__))
    after
      Code.compiler_options(compiler_options)
    end
  end

  @spec run!(module(), atom(), String.t(), Path.t(), (-> result)) :: result when result: term()
  def run!(module, application, library, directory, scenario) when is_function(scenario, 0) do
    snapshot = remember!(module)
    nif_file = copy_library!(application, library, directory)

    try do
      {:module, ^module, _binary, _load_result} = load!(module, nif_file)
      scenario.()
    after
      restore!(snapshot)
    end
  end

  defp module_body(module, nif_file) do
    stubs =
      for {name, arity} <- module.__info__(:functions), name != :load_nif do
        arguments = Macro.generate_arguments(arity, __MODULE__)

        quote do
          def unquote(name)(unquote_splicing(arguments)),
            do: :erlang.nif_error({:nif_not_loaded, unquote(name)})
        end
      end

    quote do
      @on_load :load_nif
      def load_nif, do: :erlang.load_nif(unquote(String.to_charlist(nif_file)), 0)
      unquote_splicing(stubs)
    end
  end
end
