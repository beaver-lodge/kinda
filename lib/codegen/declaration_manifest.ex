defmodule Kinda.CodeGen.DeclarationManifest do
  @moduledoc """
  A versioned declaration manifest for generated NIFs and types.

  A manifest bundles generated NIF declarations (`Kinda.CodeGen.NIFDecl`) and
  type declarations (`Kinda.CodeGen.TypeDecl`), optionally keeping the source
  signature manifest they were derived from. Manifests are the canonical
  machine-readable contract between Kinda's codegen pipeline and downstream
  consumers, and can be serialized to and from maps as well as loaded from
  `.ex` or `.json` files via `load!/1`.
  """

  alias Kinda.CodeGen.NIFDecl
  alias Kinda.CodeGen.TypeDecl

  @type source() :: t() | map() | Path.t()

  @type t() :: %__MODULE__{
          version: pos_integer(),
          signature_manifest_version: pos_integer() | nil,
          signature_manifest: map() | nil,
          nif_decls: [NIFDecl.t()],
          type_decls: [TypeDecl.t()]
        }

  defstruct version: 1,
            signature_manifest_version: nil,
            signature_manifest: nil,
            nif_decls: [],
            type_decls: []

  @spec build([NIFDecl.t()], map() | nil) :: t()
  def build(nif_decls, signature_manifest \\ nil) do
    %__MODULE__{}
    |> put_signature_manifest(signature_manifest)
    |> put_type_decls(TypeDecl.from_signature_manifest(signature_manifest))
    |> put_nif_decls(nif_decls)
  end

  @spec from_parts([NIFDecl.t()], [TypeDecl.t()], map() | nil) :: t()
  def from_parts(nif_decls, type_decls, signature_manifest \\ nil) do
    %__MODULE__{
      version: 1,
      signature_manifest_version:
        case signature_manifest do
          %{"version" => version} when is_integer(version) -> version
          _ -> nil
        end,
      signature_manifest: signature_manifest,
      nif_decls: nif_decls,
      type_decls: type_decls
    }
  end

  @spec from_manifest(map()) :: t()
  def from_manifest(%{} = manifest) do
    %__MODULE__{
      version: Map.get(manifest, "version", 1),
      signature_manifest_version: Map.get(manifest, "signature_manifest_version"),
      signature_manifest: Map.get(manifest, "signature_manifest"),
      nif_decls: manifest |> Map.get("nif_decls", []) |> Enum.map(&NIFDecl.from_manifest/1),
      type_decls: manifest |> Map.get("type_decls", []) |> Enum.map(&TypeDecl.from_manifest/1)
    }
  end

  @spec load!(source()) :: t()
  def load!(%__MODULE__{} = declaration_manifest), do: declaration_manifest

  def load!(%{} = declaration_manifest), do: from_manifest(declaration_manifest)

  def load!(path) when is_binary(path) do
    expanded_path = Path.expand(path)

    case Path.extname(expanded_path) do
      ".ex" ->
        expanded_path
        |> Code.eval_file()
        |> elem(0)
        |> load!()

      ".json" ->
        expanded_path
        |> File.read!()
        |> decode_json!()
        |> load!()

      ext ->
        raise Kinda.GenerationError,
          message: "unsupported declaration manifest source",
          stage: :declaration_loading,
          reason: :unsupported_manifest_extension,
          source: expanded_path,
          expected: [".ex", ".json"],
          actual: ext
    end
  end

  @spec signature_manifest(t()) :: map() | nil
  def signature_manifest(%__MODULE__{} = declaration_manifest),
    do: declaration_manifest.signature_manifest

  @spec signature_manifest_version(t()) :: pos_integer() | nil
  def signature_manifest_version(%__MODULE__{} = declaration_manifest),
    do: declaration_manifest.signature_manifest_version

  @spec nif_decls(t()) :: [NIFDecl.t()]
  def nif_decls(%__MODULE__{} = declaration_manifest),
    do: declaration_manifest.nif_decls

  @spec type_decls(t()) :: [TypeDecl.t()]
  def type_decls(%__MODULE__{type_decls: []} = declaration_manifest),
    do: TypeDecl.from_signature_manifest(signature_manifest(declaration_manifest))

  def type_decls(%__MODULE__{} = declaration_manifest),
    do: declaration_manifest.type_decls

  @spec put_signature_manifest(t(), map() | nil) :: t()
  def put_signature_manifest(%__MODULE__{} = declaration_manifest, signature_manifest) do
    %{
      declaration_manifest
      | signature_manifest: signature_manifest,
        signature_manifest_version:
          case signature_manifest do
            %{"version" => version} when is_integer(version) -> version
            _ -> nil
          end
    }
  end

  @spec put_nif_decls(t(), [NIFDecl.t()]) :: t()
  def put_nif_decls(%__MODULE__{} = declaration_manifest, nif_decls) when is_list(nif_decls) do
    %{declaration_manifest | nif_decls: nif_decls}
  end

  @spec merge_nif_decls(t(), [NIFDecl.t()]) :: t()
  def merge_nif_decls(%__MODULE__{} = declaration_manifest, nif_decls) when is_list(nif_decls) do
    declaration_manifest
    |> nif_decls()
    |> Kernel.++(nif_decls)
    |> Enum.uniq_by(fn %NIFDecl{wrapper_name: wrapper_name, nif_name: nif_name, params: params} ->
      {wrapper_name, nif_name, params}
    end)
    |> then(&put_nif_decls(declaration_manifest, &1))
  end

  @spec put_type_decls(t(), [TypeDecl.t()]) :: t()
  def put_type_decls(%__MODULE__{} = declaration_manifest, type_decls) when is_list(type_decls) do
    %{declaration_manifest | type_decls: type_decls}
  end

  @spec to_manifest(t()) :: map()
  def to_manifest(%__MODULE__{} = declaration_manifest) do
    %{
      "version" => declaration_manifest.version,
      "signature_manifest_version" => declaration_manifest.signature_manifest_version,
      "signature_manifest" => declaration_manifest.signature_manifest,
      "nif_decls" => Enum.map(declaration_manifest.nif_decls, &NIFDecl.to_manifest/1),
      "type_decls" => Enum.map(declaration_manifest.type_decls, &TypeDecl.to_manifest/1)
    }
  end

  defp decode_json!(json) do
    decoder =
      cond do
        Code.ensure_loaded?(JSON) and function_exported?(JSON, :decode!, 1) -> JSON
        Code.ensure_loaded?(Jason) and function_exported?(Jason, :decode!, 1) -> Jason
        true -> nil
      end

    if decoder do
      apply(decoder, :decode!, [json])
    else
      raise Kinda.GenerationError,
        message: "no JSON decoder is available for the declaration manifest",
        stage: :declaration_loading,
        reason: :missing_json_decoder,
        expected: [{JSON, :decode!, 1}, {Jason, :decode!, 1}]
    end
  end
end
