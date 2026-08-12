defmodule Kinda.Testing.Sandbox do
  @moduledoc """
  Describes an isolated native test build.

  A sandbox has a unique BEAM module, NIF entry name and output directory.
  The supplied builder must compile the native library with the given entry
  name; copying an existing library is deliberately not supported because its
  `ErlNifEntry.name` is immutable.
  """

  @enforce_keys [:id, :module, :entry_name, :directory]
  defstruct [:id, :module, :entry_name, :directory, :library]

  @type t :: %__MODULE__{
          id: pos_integer(),
          module: module(),
          entry_name: binary(),
          directory: binary(),
          library: binary() | nil
        }

  @spec new!(module(), keyword()) :: t()
  def new!(base_module, options \\ []) when is_atom(base_module) do
    id = System.unique_integer([:positive, :monotonic])
    module = Module.concat(base_module, "Sandbox#{id}")

    directory =
      Keyword.get_lazy(options, :directory, fn ->
        Path.join(System.tmp_dir!(), "kinda-sandbox-#{id}")
      end)

    File.mkdir_p!(directory)

    %__MODULE__{
      id: id,
      module: module,
      entry_name: Atom.to_string(module),
      directory: directory
    }
  end

  @doc "Builds a library through a callback that receives the sandbox contract."
  @spec build!(t(), (t() -> {:ok, binary()} | binary())) :: t()
  def build!(%__MODULE__{} = sandbox, builder) when is_function(builder, 1) do
    library =
      case builder.(sandbox) do
        {:ok, path} when is_binary(path) -> path
        path when is_binary(path) -> path
        other -> raise ArgumentError, "sandbox builder returned #{inspect(other)}"
      end

    unless File.regular?(library),
      do: raise(ArgumentError, "sandbox library does not exist: #{library}")

    %{sandbox | library: Path.expand(library)}
  end

  @spec cleanup(t()) :: :ok
  def cleanup(%__MODULE__{directory: directory}) do
    File.rm_rf!(directory)
    :ok
  end
end
