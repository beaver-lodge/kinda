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

  alias Kinda.CodeGen.{NIFDecl, TypeDecl}

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
  def build(nif_decls, signature_manifest \\ nil),
    do: from_parts(nif_decls, TypeDecl.from_signature_manifest(signature_manifest), signature_manifest)

  @spec from_parts([NIFDecl.t()], [TypeDecl.t()], map() | nil) :: t()
  def from_parts(nif_decls, type_decls, signature_manifest \\ nil),
    do: %__MODULE__{
      signature_manifest_version: source_version(signature_manifest),
      signature_manifest: signature_manifest,
      nif_decls: nif_decls,
      type_decls: type_decls
    }

  @spec from_manifest(map()) :: t()
  def from_manifest(%{} = manifest),
    do: %__MODULE__{
      version: Map.get(manifest, "version", 1),
      signature_manifest_version: Map.get(manifest, "signature_manifest_version"),
      signature_manifest: Map.get(manifest, "signature_manifest"),
      nif_decls: manifest |> Map.get("nif_decls", []) |> Enum.map(&NIFDecl.from_manifest/1),
      type_decls: manifest |> Map.get("type_decls", []) |> Enum.map(&TypeDecl.from_manifest/1)
    }

  @spec load!(source()) :: t()
  def load!(%__MODULE__{} = manifest), do: manifest

  def load!(%{} = manifest), do: from_manifest(manifest)

  def load!(path) when is_binary(path) do
    expanded_path = Path.expand(path)

    case Path.extname(expanded_path) do
      ".ex" ->
        expanded_path |> Code.eval_file() |> elem(0) |> load!()

      ".json" ->
        expanded_path |> File.read!() |> JSON.decode!() |> load!()

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
  def signature_manifest(%__MODULE__{} = manifest), do: manifest.signature_manifest

  @spec nif_decls(t()) :: [NIFDecl.t()]
  def nif_decls(%__MODULE__{} = manifest), do: manifest.nif_decls

  @spec type_decls(t()) :: [TypeDecl.t()]
  def type_decls(%__MODULE__{type_decls: []} = manifest),
    do: TypeDecl.from_signature_manifest(signature_manifest(manifest))

  def type_decls(%__MODULE__{} = manifest), do: manifest.type_decls

  @spec to_manifest(t()) :: map()
  def to_manifest(%__MODULE__{} = manifest),
    do: %{
      "version" => manifest.version,
      "signature_manifest_version" => manifest.signature_manifest_version,
      "signature_manifest" => manifest.signature_manifest,
      "nif_decls" => Enum.map(manifest.nif_decls, &NIFDecl.to_manifest/1),
      "type_decls" => Enum.map(manifest.type_decls, &TypeDecl.to_manifest/1)
    }

  defp source_version(%{"version" => version}) when is_integer(version), do: version
  defp source_version(_source), do: nil
end
