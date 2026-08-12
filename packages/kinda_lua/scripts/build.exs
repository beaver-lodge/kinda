defmodule Kinda.Lua.Build do
  @moduledoc false
  @version "5.4.8"
  @checksum "4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae"
  @url "https://www.lua.org/ftp/lua-#{@version}.tar.gz"

  def run([cache, prefix, erts_include]) do
    root = Path.expand("..", __DIR__)
    runtime = Path.join(root, ".runtime")
    archive = Path.join(runtime, "downloads/lua-#{@version}.tar.gz")
    source = Path.join(runtime, "lua-#{@version}")
    ensure_source!(archive, source)

    args =
      [
        "build",
        "--cache-dir",
        cache,
        "--prefix",
        prefix,
        "--search-prefix",
        Path.dirname(erts_include),
        "-Dlua-root=#{source}",
        "-freference-trace"
      ] ++ zig_target_args()

    run!("zig", args, root)
  end

  defp ensure_source!(archive, source) do
    unless File.dir?(source) do
      File.mkdir_p!(Path.dirname(archive))
      unless valid_checksum?(archive), do: download!(archive)
      unless valid_checksum?(archive), do: raise("Lua source checksum mismatch")
      File.mkdir_p!(Path.dirname(source))

      case :erl_tar.extract(String.to_charlist(archive), [
             :compressed,
             {:cwd, String.to_charlist(Path.dirname(source))}
           ]) do
        :ok -> :ok
        {:error, reason} -> raise "Lua source extraction failed: #{inspect(reason)}"
      end
    end
  end

  defp download!(destination) do
    :inets.start()
    :ssl.start()
    configure_proxy()

    options = [
      autoredirect: true,
      connect_timeout: 30_000,
      timeout: 180_000,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]

    case :httpc.request(:get, {String.to_charlist(@url), []}, options, body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, body}} ->
        File.write!(destination, body)

      {:ok, {{_version, status, reason}, _headers, _body}} ->
        raise "Lua source download failed with #{status}: #{reason}"

      {:error, reason} ->
        raise "Lua source download failed: #{inspect(reason)}"
    end
  end

  defp configure_proxy do
    case System.get_env("HTTPS_PROXY") || System.get_env("https_proxy") do
      nil ->
        :ok

      proxy ->
        %{host: host, port: port} = URI.parse(proxy)
        :httpc.set_options(https_proxy: {{String.to_charlist(host), port}, []})
    end
  end

  defp zig_target_args do
    if match?({:win32, _}, :os.type()) do
      architecture = System.get_env("VSCMD_ARG_TGT_ARCH", "x64")
      target = %{"x64" => "x86_64", "x86" => "x86", "arm64" => "aarch64", "arm" => "arm"}
      ["-Dtarget=#{Map.fetch!(target, architecture)}-windows-msvc"]
    else
      []
    end
  end

  defp valid_checksum?(path) do
    case File.read(path) do
      {:ok, contents} ->
        :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower) == @checksum

      {:error, _reason} ->
        false
    end
  end

  defp run!(command, args, directory) do
    {output, status} = System.cmd(command, args, cd: directory, stderr_to_stdout: true)
    IO.write(output)
    if status != 0, do: System.halt(status)
  end
end

Kinda.Lua.Build.run(System.argv())
