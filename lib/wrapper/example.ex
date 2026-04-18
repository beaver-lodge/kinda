defmodule Kinda.Wrapper.Example do
  @moduledoc """
  Runnable example for the wrapper extraction and reporting surface.
  """

  alias Kinda.Wrapper.CallbackBridge
  alias Kinda.CodeGen.TypeSpecRef
  alias Kinda.Wrapper.Extract
  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.Generate

  defmodule Policy do
    @behaviour Kinda.Wrapper.Policy

    @impl true
    def generation_blocker_entries, do: %{}

    @impl true
    def generation_blocked?(_name), do: false

    @impl true
    def generation_blocker_reason(_name), do: nil

    @impl true
    def unsupported_entries, do: generation_blocker_entries()

    @impl true
    def unsupported?(name), do: generation_blocked?(name)

    @impl true
    def unsupported_reason(name), do: generation_blocker_reason(name)

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
    def variants(:mlirContextCreate) do
      [
        {:normal, :mlirContextCreate, :mlirContextCreate},
        {:dirty_cpu, :mlirContextCreate_dirty_cpu, :mlirContextCreate}
      ]
    end

    def variants(_name), do: []

    @impl true
    def public_name({_kind, public_name, _base_name}), do: public_name

    @impl true
    def elixir_params({_kind, _public_name, _base_name}, params), do: params

    @impl true
    def dirty({:dirty_cpu, _public_name, _base_name}), do: :dirty_cpu
    def dirty({_kind, _public_name, _base_name}), do: false

    @impl true
    def doc({:dirty_cpu, _public_name, _base_name}, %Function{doc: doc}) when is_binary(doc) do
      doc <> "\n\nThis variant runs on a dirty CPU scheduler."
    end

    def doc({_kind, _public_name, _base_name}, %Function{doc: doc}), do: doc

    @impl true
    def typespec_params({_kind, _public_name, _base_name}, %Function{}), do: []

    @impl true
    def typespec_return({:dirty_cpu, _public_name, _base_name}, %Function{}),
      do: TypeSpecRef.term()

    def typespec_return({_kind, _public_name, _base_name}, %Function{}),
      do: TypeSpecRef.term()

    @impl true
    def zig_entry({:dirty_cpu, public_name, base_name}),
      do: ~s|nifDirtyCPU("#{base_name}", "#{public_name}"),|

    def zig_entry({_kind, _public_name, base_name}), do: ~s|nif("#{base_name}"),|
  end

  @spec manifest() :: Kinda.Wrapper.Manifest.t()
  def manifest do
    %{
      "kind" => "TranslationUnitDecl",
      "inner" => [
        %{
          "kind" => "RecordDecl",
          "id" => "0xctx",
          "name" => "MlirContext",
          "tagUsed" => "struct",
          "completeDefinition" => true,
          "inner" => [
            %{
              "kind" => "FieldDecl",
              "name" => "ptr",
              "type" => %{"qualType" => "const void *"}
            }
          ]
        },
        %{
          "kind" => "FunctionDecl",
          "name" => "mlirTypeConverterAddConversion",
          "inner" => [
            %{
              "kind" => "ParmVarDecl",
              "name" => "converter",
              "type" => %{"qualType" => "MlirTypeConverter"}
            }
          ],
          "type" => %{"qualType" => "void (MlirTypeConverter)"}
        },
        %{
          "kind" => "FunctionDecl",
          "name" => "mlirContextCreate",
          "type" => %{"qualType" => "MlirContext (void)"},
          "inner" => [
            %{
              "kind" => "FullComment",
              "inner" => [
                %{
                  "kind" => "ParagraphComment",
                  "inner" => [
                    %{"kind" => "TextComment", "text" => " Creates a fresh MLIR context."}
                  ]
                }
              ]
            }
          ]
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
          "\n\n== Signature Manifest ==\n",
          manifest
          |> Generate.signature_manifest(policy)
          |> encode_json(),
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
