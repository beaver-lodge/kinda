defmodule Kinda.Wrapper.Generate do
  @moduledoc """
  Generic emission helpers for wrapper manifests.
  """

  alias Kinda.Wrapper.{CallbackBridge, CField, CRecord, CType, Function, Manifest, Policy}
  alias Kinda.CodeGen.{NIFDecl, DeclarationManifest, DeclarationSurfaces, TypeSpecRef}

  @spec elixir_nif_decls(Manifest.t(), module()) :: [NIFDecl.t()]
  def elixir_nif_decls(%Manifest{functions: functions}, policy) do
    assert_policy!(policy)

    Enum.flat_map(functions, &function_nif_decls(&1, policy))
  end

  defp function_nif_decls(function, policy) do
    params = Enum.map(function.params, &String.to_atom/1)

    for variant <- policy.variants(String.to_atom(function.name)) do
      struct(NIFDecl,
        wrapper_name: policy.public_name(variant),
        params: policy.elixir_params(variant, params),
        doc: policy.doc(variant, function),
        param_ctypes: function.param_ctypes,
        return_ctype: function.return_ctype,
        param_typespecs: typespec_params(policy, variant, function),
        return_typespec: typespec_return(policy, variant, function),
        dirty: policy.dirty(variant)
      )
    end
  end

  @spec render_elixir_manifest(Manifest.t(), module()) :: String.t()
  def render_elixir_manifest(manifest, policy) do
    manifest |> elixir_nif_decls(policy) |> inspect(pretty: true, limit: :infinity, printable_limit: :infinity)
  end

  @type callback_bridge_backlog_entry :: %{function: Function.t(), callback_bridge: CallbackBridge.t()}

  @spec callback_bridge_backlog(Manifest.t(), module()) :: [callback_bridge_backlog_entry()]
  def callback_bridge_backlog(%Manifest{functions: functions}, policy) do
    assert_policy!(policy)

    Enum.flat_map(functions, fn function ->
      case policy.callback_bridge(String.to_atom(function.name)) do
        nil -> []
        %CallbackBridge{runtime_backed: true} -> []
        callback_bridge -> [%{function: function, callback_bridge: callback_bridge}]
      end
    end)
  end

  @spec render_callback_bridge_report(Manifest.t(), module()) :: String.t()
  def render_callback_bridge_report(manifest, policy) do
    manifest |> callback_bridge_backlog(policy) |> inspect(pretty: true, limit: :infinity, printable_limit: :infinity)
  end

  @spec callback_bridge_manifest(Manifest.t(), module()) :: map()
  def callback_bridge_manifest(manifest, policy) do
    entries =
      for function <- manifest.functions,
          bridge = policy.callback_bridge(String.to_atom(function.name)),
          bridge != nil do
        %{"function" => function_metadata(function), "callback_bridge" => callback_bridge_to_manifest(bridge)}
      end

    %{"version" => 2, "entries" => entries}
  end

  defp function_metadata(function),
    do: Map.new([:name, :arity, :params, :doc], &{Atom.to_string(&1), Map.fetch!(function, &1)})

  @spec signature_manifest(Manifest.t(), module()) :: map()
  def signature_manifest(%Manifest{} = manifest, policy),
    do: manifest |> declaration_surfaces_struct(policy) |> DeclarationSurfaces.signature_manifest()

  @spec declaration_surfaces_struct(Manifest.t(), module()) :: DeclarationSurfaces.t()
  def declaration_surfaces_struct(%Manifest{functions: functions, records: records} = manifest, policy) do
    assert_policy!(policy)

    signature_manifest = %{
      "version" => 1,
      "records" => Enum.map(records, &signature_manifest_record(&1, policy)),
      "entries" => Enum.map(functions, &signature_manifest_entry(&1, policy))
    }

    declaration_manifest =
      manifest |> elixir_nif_decls(policy) |> DeclarationManifest.build(signature_manifest)

    DeclarationSurfaces.from_parts(nil, declaration_manifest)
  end

  @spec declaration_manifest_struct(Manifest.t(), module()) :: DeclarationManifest.t()
  def declaration_manifest_struct(%Manifest{} = manifest, policy),
    do: manifest |> declaration_surfaces_struct(policy) |> DeclarationSurfaces.declaration_manifest()

  @spec declaration_manifest(Manifest.t(), module()) :: map()
  def declaration_manifest(%Manifest{} = manifest, policy) do
    manifest
    |> declaration_surfaces_struct(policy)
    |> DeclarationSurfaces.declaration_manifest()
    |> DeclarationManifest.to_manifest()
  end

  defp assert_policy!(policy) do
    behaviours = policy.module_info(:attributes)[:behaviour] || []

    if Policy not in behaviours do
      raise Kinda.GenerationError,
        message: "wrapper policy does not implement the required behaviour",
        stage: :wrapper_generation,
        reason: :invalid_policy,
        source: policy,
        expected: Policy
    end
  end

  defp typespec_params(policy, variant, %Function{} = function) do
    if function_exported?(policy, :typespec_params, 2) do
      policy.typespec_params(variant, function)
    else
      emitted_params =
        variant |> policy.elixir_params(Enum.map(function.params, &String.to_atom/1))

      Function.typespec_params(function, emitted_params, &CType.to_public_typespec_ref/1)
    end
  end

  defp typespec_return(policy, variant, %Function{} = function) do
    if function_exported?(policy, :typespec_return, 2) do
      policy.typespec_return(variant, function)
    else
      CType.to_public_typespec_ref(function.return_ctype)
    end
  end

  defp signature_manifest_entry(%Function{} = function, policy) do
    function_name = String.to_atom(function.name)
    blocker_reason = signature_manifest_blocker_reason(function_name, policy)

    entry = %{
      "function" =>
        Map.merge(function_metadata(function), %{
          "param_ctypes" => Enum.map(function.param_ctypes, &CType.to_manifest/1),
          "return_ctype" => CType.to_manifest(function.return_ctype)
        }),
      "generation_blocker_reason" => blocker_reason && Atom.to_string(blocker_reason),
      "variants" => signature_manifest_variants(function, policy)
    }

    case policy.callback_bridge(function_name) do
      nil -> entry
      bridge -> Map.put(entry, "callback_bridge", callback_bridge_to_manifest(bridge))
    end
  end

  defp signature_manifest_variants(%Function{} = function, policy),
    do:
      Enum.map(
        function_nif_decls(function, policy),
        &(NIFDecl.to_manifest(&1) |> Map.drop(~w(nif_name param_ctypes return_ctype)))
      )

  defp signature_manifest_record(%CRecord{} = record, policy),
    do: %{
      "name" => record.name,
      "kind" => Atom.to_string(record.kind),
      "public_typespec" => record |> typespec_record(policy) |> TypeSpecRef.to_manifest(),
      "fields" =>
        Enum.map(record.fields, fn %CField{} = field ->
          %{
            "name" => field.name,
            "ctype" => CType.to_manifest(field.ctype),
            "typespec" => record |> typespec_field(field, policy) |> TypeSpecRef.to_manifest()
          }
        end)
    }

  defp signature_manifest_blocker_reason(function_name, policy) do
    policy.generation_blocker_reason(function_name) ||
      case policy.callback_bridge(function_name) do
        nil -> nil
        %CallbackBridge{runtime_backed: true} -> nil
        bridge -> bridge.reason
      end
  end

  defp callback_bridge_to_manifest(%CallbackBridge{} = bridge),
    do: %{
      "function" => Atom.to_string(bridge.function),
      "reason" => bridge.reason && Atom.to_string(bridge.reason),
      "unblock_path" => bridge.unblock_path && Atom.to_string(bridge.unblock_path),
      "scheduler" => Atom.to_string(bridge.scheduler),
      "facets" => Enum.map(bridge.facets, &Atom.to_string/1),
      "runtime" => Atom.to_string(bridge.runtime),
      "runtime_backed" => bridge.runtime_backed,
      "owner" => Atom.to_string(bridge.owner),
      "destructor" => Atom.to_string(bridge.destructor),
      "lifetime" => Atom.to_string(bridge.lifetime),
      "timeout_ms" => bridge.timeout_ms
    }

  defp typespec_field(%CRecord{} = record, %CField{} = field, policy) do
    if function_exported?(policy, :typespec_field, 2) do
      policy.typespec_field(record, field)
    else
      CType.to_public_typespec_ref(field.ctype)
    end
  end

  defp typespec_record(%CRecord{} = record, policy) do
    if function_exported?(policy, :typespec_record, 1) do
      policy.typespec_record(record)
    else
      TypeSpecRef.map(
        Enum.map(record.fields, fn %CField{name: name} = field -> {name, typespec_field(record, field, policy)} end)
      )
    end
  end
end
