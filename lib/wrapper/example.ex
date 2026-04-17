defmodule Kinda.Wrapper.Example do
  @moduledoc """
  Runnable example for the wrapper extraction and reporting surface.
  """

  alias Kinda.Wrapper.CallbackBridge
  alias Kinda.Wrapper.Extract
  alias Kinda.Wrapper.Generate

  defmodule Policy do
    @behaviour Kinda.Wrapper.Policy

    @impl true
    def unsupported_entries, do: %{}

    @impl true
    def unsupported?(_name), do: false

    @impl true
    def unsupported_reason(_name), do: nil

    @impl true
    def callback_bridge_entries do
      %{
        mlirTypeConverterAddConversion:
          CallbackBridge.required(:mlirTypeConverterAddConversion,
            facets: [:beam_callback, :rich_input_decoder]
          )
      }
    end

    @impl true
    def callback_bridge?(name), do: Map.has_key?(callback_bridge_entries(), name)

    @impl true
    def callback_bridge(name), do: Map.get(callback_bridge_entries(), name)

    @impl true
    def variants(:mlirContextCreate), do: [{:normal, :mlirContextCreate, :mlirContextCreate}]

    def variants(_name), do: []

    @impl true
    def public_name({_kind, public_name, _base_name}), do: public_name

    @impl true
    def elixir_params({_kind, _public_name, _base_name}, params), do: params

    @impl true
    def zig_entry({_kind, _public_name, base_name}), do: ~s|nif("#{base_name}"),|
  end

  @spec manifest() :: Kinda.Wrapper.Manifest.t()
  def manifest do
    %{
      "kind" => "TranslationUnitDecl",
      "inner" => [
        %{
          "kind" => "FunctionDecl",
          "name" => "mlirTypeConverterAddConversion",
          "inner" => [
            %{"kind" => "ParmVarDecl", "name" => "converter"}
          ]
        },
        %{
          "kind" => "FunctionDecl",
          "name" => "mlirContextCreate",
          "inner" => []
        }
      ]
    }
    |> Extract.from_clang_ast()
  end

  @type render_mode() :: :all | :json | :report_only

  @spec render(keyword()) :: String.t()
  def render(opts \\ []) do
    manifest = manifest()
    policy = Policy

    case output_mode(opts) do
      :json ->
        manifest
        |> Generate.callback_bridge_manifest(policy)
        |> encode_json()
        |> Kernel.<>("\n")

      :report_only ->
        [
          "== Callback Bridge Report ==\n",
          Generate.render_callback_bridge_report(manifest, policy),
          "\n"
        ]
        |> IO.iodata_to_binary()

      :all ->
        [
          "== Elixir Manifest ==\n",
          Generate.render_elixir_manifest(manifest, policy),
          "\n\n== Callback Bridge Report ==\n",
          Generate.render_callback_bridge_report(manifest, policy),
          "\n\n== Callback Bridge Manifest ==\n",
          manifest
          |> Generate.callback_bridge_manifest(policy)
          |> encode_json(),
          "\n"
        ]
        |> IO.iodata_to_binary()
    end
  end

  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    IO.write(render(opts))
  end

  defp output_mode(opts) do
    cond do
      Keyword.get(opts, :json, false) -> :json
      Keyword.get(opts, :report_only, false) -> :report_only
      true -> :all
    end
  end

  defp encode_json(term) do
    apply(json_mod(), :encode!, [term])
  end

  defp json_mod do
    if Version.match?(System.version(), "< 1.18.0"), do: Jason, else: JSON
  end
end
