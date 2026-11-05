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
    @moduledoc false

    @behaviour Kinda.Wrapper.Policy

    @impl true
    def generation_blocker_entries, do: %{}

    @impl true
    def generation_blocked?(_name), do: false

    @impl true
    def generation_blocker_reason(_name), do: nil

    @impl true
    def callback_bridge_entries do
      %{
        mlirTypeConverterAddConversion:
          CallbackBridge.required(:mlirTypeConverterAddConversion, facets: [:beam_callback, :rich_input_decoder])
      }
    end

    @impl true
    def callback_bridge?(name), do: Map.has_key?(callback_bridge_entries(), name)

    @impl true
    def callback_bridge(name), do: Map.get(callback_bridge_entries(), name)

    @impl true
    def variants(:mlirContextCreate),
      do: [
        {:normal, :mlirContextCreate, :mlirContextCreate},
        {:dirty_cpu, :mlirContextCreate_dirty_cpu, :mlirContextCreate}
      ]

    def variants(_name), do: []

    @impl true
    def public_name({_kind, public_name, _base_name}), do: public_name

    @impl true
    def elixir_params({_kind, _public_name, _base_name}, params), do: params

    @impl true
    def dirty({:dirty_cpu, _public_name, _base_name}), do: :dirty_cpu
    def dirty({_kind, _public_name, _base_name}), do: false

    @impl true
    def doc({:dirty_cpu, _public_name, _base_name}, %Function{doc: doc}) when is_binary(doc),
      do: doc <> "\n\nThis variant runs on a dirty CPU scheduler."

    def doc({_kind, _public_name, _base_name}, %Function{doc: doc}), do: doc

    @impl true
    def typespec_params({_kind, _public_name, _base_name}, %Function{}), do: []

    @impl true
    def typespec_return({_kind, _public_name, _base_name}, %Function{}), do: TypeSpecRef.term()
  end

  @spec manifest() :: Kinda.Wrapper.Manifest.t()
  def manifest do
    node("TranslationUnitDecl", [], [
      node("RecordDecl", [id: "0xctx", name: "MlirContext", tagUsed: "struct", completeDefinition: true], [
        typed_node("FieldDecl", "ptr", "const void *")
      ]),
      typed_node("FunctionDecl", "mlirTypeConverterAddConversion", "void (MlirTypeConverter)", [
        typed_node("ParmVarDecl", "converter", "MlirTypeConverter")
      ]),
      typed_node("FunctionDecl", "mlirContextCreate", "MlirContext (void)", [
        node("FullComment", [], [
          node("ParagraphComment", [], [node("TextComment", text: " Creates a fresh MLIR context.")])
        ])
      ])
    ])
    |> Extract.from_clang_ast()
  end

  defp node(kind, attributes, inner \\ []),
    do: Map.new([{:kind, kind}, {:inner, inner} | attributes], fn {key, value} -> {Atom.to_string(key), value} end)

  defp typed_node(kind, name, type, inner \\ []), do: node(kind, [name: name, type: %{"qualType" => type}], inner)

  @type render_mode() :: :all | :json | :report_only

  @spec render(keyword()) :: String.t()
  def render(opts \\ []) do
    manifest = manifest()
    policy = Policy

    case output_mode(opts) do
      :json ->
        manifest |> Generate.callback_bridge_manifest(policy) |> encode_json() |> Kernel.<>("\n")

      :report_only ->
        ["== Callback Bridge Report ==\n", Generate.render_callback_bridge_report(manifest, policy), "\n"]
        |> IO.iodata_to_binary()

      :all ->
        [
          {"Elixir Manifest", Generate.render_elixir_manifest(manifest, policy)},
          {"Declaration Manifest", encode_json(Generate.declaration_manifest(manifest, policy))},
          {"Derived Signature Manifest", encode_json(Generate.signature_manifest(manifest, policy))},
          {"Callback Bridge Report", Generate.render_callback_bridge_report(manifest, policy)},
          {"Callback Bridge Manifest", encode_json(Generate.callback_bridge_manifest(manifest, policy))}
        ]
        |> Enum.map_join("\n\n", fn {title, content} -> "== #{title} ==\n#{content}" end)
        |> Kernel.<>("\n")
    end
  end

  @spec run(keyword()) :: :ok
  def run(opts \\ []), do: IO.write(render(opts))

  defp output_mode(opts) do
    cond do
      Keyword.get(opts, :json, false) -> :json
      Keyword.get(opts, :report_only, false) -> :report_only
      true -> :all
    end
  end

  defp encode_json(term), do: JSON.encode!(term)
end
