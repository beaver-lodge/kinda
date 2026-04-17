defmodule Kinda.Wrapper.Generate do
  @moduledoc """
  Generic emission helpers for wrapper manifests.
  """

  alias Kinda.Wrapper.CallbackBridge
  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.Manifest
  alias Kinda.Wrapper.Policy

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

  @spec render_elixir_manifest(Manifest.t(), module()) :: String.t()
  def render_elixir_manifest(manifest, policy) do
    manifest
    |> elixir_functions(policy)
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
          String.t() => String.t() | non_neg_integer() | [String.t()]
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
        Enum.map(callback_bridge_backlog(manifest, policy), fn %{function: function, callback_bridge: bridge} ->
          %{
            "function" => %{
              "name" => function.name,
              "arity" => function.arity,
              "params" => function.params
            },
            "callback_bridge" => %{
              "function" => Atom.to_string(bridge.function),
              "reason" => Atom.to_string(bridge.reason),
              "scheduler" => Atom.to_string(bridge.scheduler),
              "facets" => Enum.map(bridge.facets, &Atom.to_string/1)
            }
          }
        end)
    }
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

  def write_callback_bridge_manifest(manifest, policy, path, encoder) when is_function(encoder, 1) do
    manifest
    |> callback_bridge_manifest(policy)
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
end
