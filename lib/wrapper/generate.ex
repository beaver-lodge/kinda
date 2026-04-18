defmodule Kinda.Wrapper.Generate do
  @moduledoc """
  Generic emission helpers for wrapper manifests.
  """

  alias Kinda.Wrapper.CallbackBridge
  alias Kinda.Wrapper.CField
  alias Kinda.Wrapper.CRecord
  alias Kinda.Wrapper.CType
  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.Manifest
  alias Kinda.Wrapper.Policy
  alias Kinda.CodeGen.NIFDecl
  alias Kinda.CodeGen.DeclarationManifest
  alias Kinda.CodeGen.TypeSpecRef

  @spec elixir_functions(Manifest.t(), module()) :: [{atom(), [atom()]}]
  def elixir_functions(%Manifest{functions: functions}, policy) do
    assert_policy!(policy)

    Enum.flat_map(functions, fn function ->
      name = String.to_atom(function.name)
      params = Enum.map(function.params, &String.to_atom/1)

      for variant <- policy.variants(name) do
        {policy.public_name(variant), policy.elixir_params(variant, params)}
      end
    end)
  end

  @spec elixir_nif_decls(Manifest.t(), module()) :: [NIFDecl.t()]
  def elixir_nif_decls(%Manifest{functions: functions}, policy) do
    assert_policy!(policy)

    Enum.flat_map(functions, fn function ->
      name = String.to_atom(function.name)
      params = Enum.map(function.params, &String.to_atom/1)

      for variant <- policy.variants(name) do
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
    end)
  end

  @spec render_elixir_manifest(Manifest.t(), module()) :: String.t()
  def render_elixir_manifest(manifest, policy) do
    manifest
    |> elixir_nif_decls(policy)
    |> inspect(pretty: true, limit: :infinity, printable_limit: :infinity)
  end

  @spec zig_entries(Manifest.t(), module()) :: [String.t()]
  def zig_entries(%Manifest{functions: functions}, policy) do
    assert_policy!(policy)

    Enum.flat_map(functions, fn function ->
      function.name
      |> String.to_atom()
      |> policy.variants()
      |> Enum.map(&policy.zig_entry/1)
    end)
  end

  @type callback_bridge_backlog_entry :: %{
          function: Function.t(),
          callback_bridge: CallbackBridge.t()
        }

  @type callback_bridge_manifest_function :: %{
          String.t() => String.t() | non_neg_integer() | [String.t()] | nil
        }

  @type callback_bridge_manifest_metadata :: %{
          String.t() => String.t() | [String.t()]
        }

  @type callback_bridge_manifest_entry :: %{
          String.t() => callback_bridge_manifest_function() | callback_bridge_manifest_metadata()
        }

  @type callback_bridge_manifest :: %{
          String.t() => pos_integer() | [callback_bridge_manifest_entry()]
        }

  @type signature_manifest_function :: %{
          String.t() =>
            String.t() | non_neg_integer() | [String.t() | nil] | map() | [map() | nil] | nil
        }

  @type signature_manifest_variant :: %{
          String.t() => String.t() | false | [String.t()] | [map()] | map() | nil
        }

  @type signature_manifest_record_field :: %{
          String.t() => String.t() | map() | nil
        }

  @type signature_manifest_record :: %{
          String.t() => String.t() | map() | [signature_manifest_record_field()]
        }

  @type signature_manifest_entry :: %{
          String.t() =>
            signature_manifest_function() | [signature_manifest_variant()] | String.t() | nil
        }

  @type signature_manifest :: %{
          String.t() =>
            pos_integer() | [signature_manifest_entry()] | [signature_manifest_record()]
        }

  @type declaration_manifest_struct :: DeclarationManifest.t()
  @type declaration_manifest :: map()

  @spec callback_bridge_backlog(Manifest.t(), module()) :: [callback_bridge_backlog_entry()]
  def callback_bridge_backlog(%Manifest{functions: functions}, policy) do
    assert_policy!(policy)

    Enum.flat_map(functions, fn function ->
      case policy.callback_bridge(String.to_atom(function.name)) do
        nil -> []
        callback_bridge -> [%{function: function, callback_bridge: callback_bridge}]
      end
    end)
  end

  @spec render_callback_bridge_report(Manifest.t(), module()) :: String.t()
  def render_callback_bridge_report(manifest, policy) do
    manifest
    |> callback_bridge_backlog(policy)
    |> inspect(pretty: true, limit: :infinity, printable_limit: :infinity)
  end

  @spec callback_bridge_manifest(Manifest.t(), module()) :: callback_bridge_manifest()
  def callback_bridge_manifest(manifest, policy) do
    %{
      "version" => 1,
      "entries" =>
        Enum.map(callback_bridge_backlog(manifest, policy), fn %{
                                                                 function: function,
                                                                 callback_bridge: bridge
                                                               } ->
          %{
            "function" => %{
              "name" => function.name,
              "arity" => function.arity,
              "params" => function.params,
              "doc" => function.doc
            },
            "callback_bridge" => %{
              "function" => Atom.to_string(bridge.function),
              "reason" => Atom.to_string(bridge.reason),
              "unblock_path" => Atom.to_string(bridge.unblock_path),
              "scheduler" => Atom.to_string(bridge.scheduler),
              "facets" => Enum.map(bridge.facets, &Atom.to_string/1)
            }
          }
        end)
    }
  end

  @spec signature_manifest(Manifest.t(), module()) :: signature_manifest()
  def signature_manifest(%Manifest{} = manifest, policy) do
    manifest
    |> declaration_manifest_struct(policy)
    |> DeclarationManifest.signature_manifest()
  end

  @spec declaration_manifest_struct(Manifest.t(), module()) :: declaration_manifest_struct()
  def declaration_manifest_struct(%Manifest{functions: functions, records: records} = manifest, policy) do
    assert_policy!(policy)

    signature_manifest = %{
      "version" => 1,
      "records" => Enum.map(records, &signature_manifest_record(&1, policy)),
      "entries" => Enum.map(functions, &signature_manifest_entry(&1, policy))
    }

    manifest
    |> elixir_nif_decls(policy)
    |> DeclarationManifest.build(signature_manifest)
  end

  @spec declaration_manifest(Manifest.t(), module()) :: declaration_manifest()
  def declaration_manifest(%Manifest{} = manifest, policy) do
    manifest
    |> declaration_manifest_struct(policy)
    |> DeclarationManifest.to_manifest()
  end

  @spec render_zig_nif_entries(Manifest.t(), module()) :: String.t()
  def render_zig_nif_entries(manifest, policy) do
    entries = zig_entries(manifest, policy)

    """
    const e = @import("kinda").erl_nif;
    pub fn nif_entries(comptime prelude: anytype, comptime diagnostic: anytype) [#{length(entries)}]e.ErlNifFunc {
        const nif = prelude.nif;
        const nifDirtyCPU = prelude.nifDirtyCPU;
        const nifDirtyIO = prelude.nifDirtyIO;
        return .{
        #{Enum.join(entries, "\n")}
        };
    }
    """
  end

  @spec write_elixir_manifest(Manifest.t(), module(), nil | String.t()) :: :ok
  def write_elixir_manifest(_manifest, _policy, nil), do: :ok

  def write_elixir_manifest(manifest, policy, path) do
    path
    |> Path.expand()
    |> write_file(render_elixir_manifest(manifest, policy))
  end

  @spec write_zig_nif_entries(Manifest.t(), module(), nil | String.t()) :: :ok
  def write_zig_nif_entries(_manifest, _policy, nil), do: :ok

  def write_zig_nif_entries(manifest, policy, path) do
    dst = Path.expand(path)
    write_file(dst, render_zig_nif_entries(manifest, policy))
    {_output, 0} = System.cmd("zig", ["fmt", dst], stderr_to_stdout: true)
    :ok
  end

  @spec write_callback_bridge_report(Manifest.t(), module(), nil | String.t()) :: :ok
  def write_callback_bridge_report(_manifest, _policy, nil), do: :ok

  def write_callback_bridge_report(manifest, policy, path) do
    path
    |> Path.expand()
    |> write_file(render_callback_bridge_report(manifest, policy))
  end

  @spec write_callback_bridge_manifest(
          Manifest.t(),
          module(),
          nil | String.t(),
          (callback_bridge_manifest() -> iodata())
        ) :: :ok
  def write_callback_bridge_manifest(_manifest, _policy, nil, _encoder), do: :ok

  def write_callback_bridge_manifest(manifest, policy, path, encoder)
      when is_function(encoder, 1) do
    manifest
    |> callback_bridge_manifest(policy)
    |> encoder.()
    |> IO.iodata_to_binary()
    |> then(&write_file(Path.expand(path), &1))
  end

  @spec write_signature_manifest(
          Manifest.t(),
          module(),
          nil | String.t(),
          (signature_manifest() -> iodata())
        ) :: :ok
  def write_signature_manifest(_manifest, _policy, nil, _encoder), do: :ok

  def write_signature_manifest(manifest, policy, path, encoder)
      when is_function(encoder, 1) do
    manifest
    |> declaration_manifest_struct(policy)
    |> DeclarationManifest.signature_manifest()
    |> encoder.()
    |> IO.iodata_to_binary()
    |> then(&write_file(Path.expand(path), &1))
  end

  @spec write_declaration_manifest(
          Manifest.t(),
          module(),
          nil | String.t(),
          (declaration_manifest() -> iodata())
        ) :: :ok
  def write_declaration_manifest(_manifest, _policy, nil, _encoder), do: :ok

  def write_declaration_manifest(manifest, policy, path, encoder)
      when is_function(encoder, 1) do
    manifest
    |> declaration_manifest_struct(policy)
    |> DeclarationManifest.to_manifest()
    |> encoder.()
    |> IO.iodata_to_binary()
    |> then(&write_file(Path.expand(path), &1))
  end

  defp write_file(dst, txt) do
    tmp_dir = System.get_env("MIX_APP_PATH") || System.tmp_dir() || make_tmp_dir()
    tmp = Path.join(tmp_dir, "tmp-#{System.pid()}--#{Path.basename(dst)}")
    File.touch!(tmp)

    try do
      File.write!(tmp, txt)
      File.rename!(tmp, dst)
      :ok
    rescue
      error ->
        File.rm(tmp)
        reraise error, __STACKTRACE__
    end
  end

  defp make_tmp_dir do
    tmp_dir = Path.expand("./tmp")
    File.mkdir_p!(tmp_dir)
    tmp_dir
  end

  defp assert_policy!(policy) do
    behaviours = policy.module_info(:attributes)[:behaviour] || []

    if Policy not in behaviours do
      raise ArgumentError,
            "expected #{inspect(policy)} to implement #{inspect(Policy)}"
    end
  end

  defp typespec_params(policy, variant, %Function{} = function) do
    if function_exported?(policy, :typespec_params, 2) do
      policy.typespec_params(variant, function)
    else
      emitted_params =
        variant
        |> policy.elixir_params(Enum.map(function.params, &String.to_atom/1))

      Function.typespec_params(function, emitted_params, &CType.to_public_typespec_ref/1)
    end
  end

  defp typespec_return(policy, variant, %Function{} = function) do
    if function_exported?(policy, :typespec_return, 2) do
      policy.typespec_return(variant, function)
    else
      function.return_ctype
      |> CType.to_public_typespec_ref()
      |> default_return_typespec()
    end
  end

  defp default_return_typespec(typespec)
       when typespec in [:ok, :boolean, :integer, :float, :term],
       do: typespec

  defp default_return_typespec(typespec) do
    TypeSpecRef.union([typespec, TypeSpecRef.term()])
  end

  defp signature_manifest_entry(%Function{} = function, policy) do
    function_name = String.to_atom(function.name)
    blocker_reason = signature_manifest_blocker_reason(function_name, policy)

    %{
      "function" => %{
        "name" => function.name,
        "arity" => function.arity,
        "params" => function.params,
        "doc" => function.doc,
        "param_ctypes" => Enum.map(function.param_ctypes, &CType.to_manifest/1),
        "return_ctype" => CType.to_manifest(function.return_ctype)
      },
      "generation_blocker_reason" => blocker_reason && Atom.to_string(blocker_reason),
      "variants" => signature_manifest_variants(function, function_name, policy)
    }
  end

  defp signature_manifest_variants(%Function{} = function, function_name, policy) do
    params = Enum.map(function.params, &String.to_atom/1)

    for variant <- policy.variants(function_name) do
      %{
        "wrapper_name" => variant |> policy.public_name() |> Atom.to_string(),
        "params" =>
          variant
          |> policy.elixir_params(params)
          |> Enum.map(&Atom.to_string/1),
        "doc" => policy.doc(variant, function),
        "dirty" => encode_dirty(policy.dirty(variant)),
        "param_typespecs" =>
          typespec_params(policy, variant, function)
          |> Enum.map(&TypeSpecRef.to_manifest/1),
        "return_typespec" =>
          typespec_return(policy, variant, function)
          |> TypeSpecRef.to_manifest()
      }
    end
  end

  defp encode_dirty(false), do: false
  defp encode_dirty(dirty), do: Atom.to_string(dirty)

  defp signature_manifest_record(%CRecord{} = record, policy) do
    %{
      "name" => record.name,
      "kind" => Atom.to_string(record.kind),
      "public_typespec" =>
        record
        |> typespec_record(policy)
        |> TypeSpecRef.to_manifest(),
      "fields" =>
        Enum.map(record.fields, fn %CField{} = field ->
          %{
            "name" => field.name,
            "ctype" => CType.to_manifest(field.ctype),
            "typespec" =>
              record
              |> typespec_field(field, policy)
              |> TypeSpecRef.to_manifest()
          }
        end)
    }
  end

  defp signature_manifest_blocker_reason(function_name, policy) do
    policy.generation_blocker_reason(function_name) ||
      case policy.callback_bridge(function_name) do
        nil -> nil
        bridge -> bridge.reason
      end
  end

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
        Enum.map(record.fields, fn %CField{name: name} = field ->
          {name, typespec_field(record, field, policy)}
        end)
      )
    end
  end
end
