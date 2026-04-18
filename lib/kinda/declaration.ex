defmodule Kinda.Declaration do
  @moduledoc """
  Canonical downstream entry point for Kinda's formalized declaration contract.

  Consumer repos should prefer this module over reaching directly into
  `Kinda.CodeGen.*` when they need to:

  - load a generator's declaration source
  - resolve generator output into declaration surfaces
  - inspect generated NIF and type declarations

  The underlying IR still lives in `Kinda.CodeGen.DeclarationSurfaces`, but
  this facade is the intended stable binding/declaration surface for
  downstreams.

  That boundary is intentionally independent from downstream DSL naming.
  Repos such as Beaver can rename or consolidate their public IR, dialect,
  rewrite, and pass surfaces, including collapsing historical shim layers,
  without pulling declaration resolution back out of `kinda`.
  """

  alias Kinda.CodeGen.{DeclarationManifest, DeclarationSurfaces, NIFDecl, TypeDecl}

  @type manifest() :: DeclarationManifest.t()
  @type source() :: DeclarationManifest.source()
  @type surfaces() :: DeclarationSurfaces.t()
  @type nif_decl() :: NIFDecl.t()
  @type type_decl() :: TypeDecl.t()

  @spec load_source(module()) :: DeclarationSurfaces.source_declaration_manifest()
  defdelegate load_source(mod), to: DeclarationSurfaces

  @spec from_generator(module(), module()) :: surfaces()
  defdelegate from_generator(mod, root_module), to: DeclarationSurfaces

  @spec from_parts(DeclarationSurfaces.source_declaration_manifest(), manifest()) :: surfaces()
  defdelegate from_parts(source_declaration_manifest, declaration_manifest),
    to: DeclarationSurfaces

  @spec source_declaration_manifest(surfaces()) ::
          DeclarationSurfaces.source_declaration_manifest()
  defdelegate source_declaration_manifest(surfaces), to: DeclarationSurfaces

  @spec declaration_manifest(surfaces()) :: manifest()
  defdelegate declaration_manifest(surfaces), to: DeclarationSurfaces

  @spec signature_manifest(surfaces()) :: map() | nil
  defdelegate signature_manifest(surfaces), to: DeclarationSurfaces

  @spec nif_decls(surfaces()) :: [nif_decl()]
  defdelegate nif_decls(surfaces), to: DeclarationSurfaces

  @spec type_decls(surfaces()) :: [type_decl()]
  defdelegate type_decls(surfaces), to: DeclarationSurfaces
end
