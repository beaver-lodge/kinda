defmodule Kinda.MRuby.Build do
  @moduledoc false

  @version "4.0.0"
  @checksum "e2ea271dbed14e9f2b33df773ae447b747dbc242ce2675022c0a57efea85a7b4"
  @url "https://github.com/mruby/mruby/archive/refs/tags/#{@version}.tar.gz"
  @build_profile "mruby-4.0.0-pic-v4-word-boxing-int64"

  def run([cache, prefix, erts_include]) do
    root = Path.expand("..", __DIR__)
    runtime = Path.join(root, ".runtime")
    archive = Path.join(runtime, "downloads/mruby-#{@version}.tar.gz")
    source = Path.join(runtime, "mruby-#{@version}")

    ensure_source!(archive, source)
    build_mruby!(root, source)
    shim_object = build_windows_shim!(root, source)

    args =
      [
        "build",
        "--cache-dir",
        cache,
        "--prefix",
        prefix,
        "--search-prefix",
        Path.dirname(erts_include),
        "-Dmruby-root=#{source}",
        "-freference-trace"
      ] ++ zig_target_args() ++ zig_shim_args(shim_object)

    run!("zig", args, root)
  end

  defp ensure_source!(archive, source) do
    unless File.dir?(source) do
      File.mkdir_p!(Path.dirname(archive))

      unless valid_checksum?(archive) do
        download!(archive)
      end

      unless valid_checksum?(archive), do: raise("mruby source checksum mismatch")
      File.mkdir_p!(Path.dirname(source))

      case :erl_tar.extract(String.to_charlist(archive), [
             :compressed,
             {:cwd, String.to_charlist(Path.dirname(source))}
           ]) do
        :ok -> :ok
        {:error, reason} -> raise "mruby source extraction failed: #{inspect(reason)}"
      end
    end
  end

  defp build_mruby!(root, source) do
    ruby = System.find_executable("ruby") || raise "Ruby is required to build mruby"
    config = Path.join(root, "scripts/mruby_build_config.rb")
    library = Path.join([source, "build", "host", "lib", library_name()])
    marker = Path.join([source, "build", ".kinda-profile"])

    unless File.exists?(library) and File.exists?(marker) and File.read!(marker) == @build_profile do
      File.rm_rf!(Path.join(source, "build"))

      env =
        [
          {"MRUBY_CONFIG", config},
          {"KINDA_MRUBY_TOOLCHAIN",
           if(match?({:win32, _}, :os.type()), do: "visualcpp", else: "gcc")}
        ] ++ windows_toolchain_env()

      run!(ruby, ["minirake"], source, env)
      File.write!(marker, @build_profile)
    end
  end

  defp library_name do
    if match?({:win32, _}, :os.type()), do: "libmruby.lib", else: "libmruby.a"
  end

  defp windows_toolchain_env do
    if match?({:win32, _}, :os.type()) do
      [{"LD", ~s("#{msvc_linker!()}")}]
    else
      []
    end
  end

  defp build_windows_shim!(root, source) do
    if match?({:win32, _}, :os.type()) do
      compiler = System.find_executable("cl.exe") || raise "MSVC compiler is required"
      object = Path.join([source, "build", "host", "lib", "kinda_mruby_shim.obj"])

      args = [
        "/nologo",
        "/c",
        "/O2",
        "/std:c11",
        "/W3",
        "/MD",
        "/DMRB_NO_DEFAULT_RO_DATA_P",
        "/DMRB_WORD_BOXING",
        "/DMRB_INT64",
        "/I#{Path.join(root, "native/include")}",
        "/I#{Path.join(source, "include")}",
        "/I#{Path.join([source, "build", "host", "include"])}",
        "/Fo#{object}",
        Path.join([root, "native", "c-src", "kinda_mruby_shim.c"])
      ]

      run!(compiler, args, root)
      object
    end
  end

  defp zig_shim_args(nil), do: []
  defp zig_shim_args(object), do: ["-Dmruby-shim-object=#{object}"]

  defp msvc_linker! do
    tools = System.get_env("VCToolsInstallDir") || raise "VCToolsInstallDir is not set"
    host = System.get_env("VSCMD_ARG_HOST_ARCH", "x64")
    target = System.get_env("VSCMD_ARG_TGT_ARCH", "x64")
    linker = Path.join([tools, "bin", "Host#{host}", target, "link.exe"])

    if File.exists?(linker), do: linker, else: raise("MSVC linker not found at #{linker}")
  end

  defp zig_target_args do
    if match?({:win32, _}, :os.type()) do
      architecture = zig_architecture!(System.get_env("VSCMD_ARG_TGT_ARCH"))
      ["-Dtarget=#{architecture}-windows-msvc"]
    else
      []
    end
  end

  defp zig_architecture!("x64"), do: "x86_64"
  defp zig_architecture!("x86"), do: "x86"
  defp zig_architecture!("arm64"), do: "aarch64"
  defp zig_architecture!("arm"), do: "arm"

  defp zig_architecture!(architecture),
    do: raise("unsupported MSVC architecture: #{architecture}")

  defp valid_checksum?(path) do
    case File.read(path) do
      {:ok, contents} -> sha256(contents) == @checksum
      {:error, _reason} -> false
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
        raise "mruby source download failed with #{status}: #{reason}"

      {:error, reason} ->
        raise "mruby source download failed: #{inspect(reason)}"
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

  defp sha256(contents), do: :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)

  defp run!(command, args, directory, env \\ []) do
    {output, status} = System.cmd(command, args, cd: directory, env: env, stderr_to_stdout: true)
    IO.write(output)
    if status != 0, do: System.halt(status)
  end
end

Kinda.MRuby.Build.run(System.argv())
