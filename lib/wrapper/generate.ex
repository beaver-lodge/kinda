defmodule Kinda.Wrapper.Generate do
  @moduledoc """
  Generic emission helpers for wrapper manifests.
  """

  alias Kinda.Wrapper.Manifest

  @spec elixir_functions(Manifest.t(), module()) :: [{atom(), [atom()]}]
  def elixir_functions(%Manifest{functions: functions}, policy) do
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
    Enum.flat_map(functions, fn function ->
      function.name
      |> String.to_atom()
      |> policy.variants()
      |> Enum.map(&policy.zig_entry/1)
    end)
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
end
