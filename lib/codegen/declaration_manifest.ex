defmodule Kinda.CodeGen.DeclarationManifest do
  @moduledoc false

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
        raise ArgumentError,
              "expected declaration manifest source to be a map, struct, or .ex/.json path, got extension #{inspect(ext)}"
    end
  end

  @spec signature_manifest(t()) :: map() | nil
  def signature_manifest(%__MODULE__{} = declaration_manifest),
    do: declaration_manifest.signature_manifest

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
      raise ArgumentError,
            "loading JSON declaration manifests requires JSON.decode!/1 or Jason.decode!/1 to be available"
    end
  end
end
