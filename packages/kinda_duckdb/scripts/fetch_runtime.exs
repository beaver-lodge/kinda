defmodule Kinda.DuckDB.RuntimeFetcher do
  @moduledoc false

  @version "v1.5.5"
  @release_url "https://github.com/duckdb/duckdb/releases/download/#{@version}"

  @assets %{
    "linux-amd64" =>
      {"libduckdb-linux-amd64.zip",
       "1fb8ce388157d84a25abe685a8a2520bf00c00321821968e4bb398fd766e7abb"},
    "linux-arm64" =>
      {"libduckdb-linux-arm64.zip",
       "abe4f6f005ee0b448a058322f4263584b4bd1b6faf7ab4637b79eeaf978f8e9c"},
    "osx-universal" =>
      {"libduckdb-osx-universal.zip",
       "7b5b8915cc382d0708636fe6385c0cdad5a61c9ff8ba2638b3e2141640783155"},
    "windows-amd64" =>
      {"libduckdb-windows-amd64.zip",
       "8375eb1fcf2212e8a0817950354815d4dde9dd383c2d9fa7b8975b71e278c1bd"}
  }

  def run do
    target = System.get_env("KINDA_DUCKDB_TARGET") || host_target()
    {asset, checksum} = Map.fetch!(@assets, target)
    root = Path.expand("..", __DIR__)
    archive = Path.join([root, ".runtime", "downloads", @version, asset])

    ensure_archive!(archive, asset, checksum)
    install!(root, archive)
  end

  defp host_target do
    architecture = :erlang.system_info(:system_architecture) |> List.to_string()

    cond do
      match?({:win32, _name}, :os.type()) -> "windows-amd64"
      architecture =~ ~r/^x86_64-.*linux/ -> "linux-amd64"
      architecture =~ ~r/^(aarch64|arm64)-.*linux/ -> "linux-arm64"
      architecture =~ ~r/^(x86_64|aarch64|arm64)-apple-darwin/ -> "osx-universal"
      architecture =~ ~r/^x86_64-.*(mingw|windows|win32)/ -> "windows-amd64"
      true -> raise "unsupported DuckDB runtime target: #{architecture}"
    end
  end

  defp ensure_archive!(archive, asset, checksum) do
    if valid_checksum?(archive, checksum) do
      :ok
    else
      File.mkdir_p!(Path.dirname(archive))
      download!(@release_url <> "/" <> asset, archive)

      unless valid_checksum?(archive, checksum) do
        raise "DuckDB runtime checksum mismatch for #{asset}"
      end
    end
  end

  defp valid_checksum?(path, checksum) do
    case File.read(path) do
      {:ok, contents} -> sha256(contents) == checksum
      {:error, _reason} -> false
    end
  end

  defp download!(url, destination) do
    :inets.start()
    :ssl.start()
    configure_proxy()

    ssl_options = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    request = {String.to_charlist(url), []}

    http_options = [
      autoredirect: true,
      connect_timeout: 30_000,
      timeout: 180_000,
      ssl: ssl_options
    ]

    case :httpc.request(:get, request, http_options, body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, body}} ->
        File.write!(destination, body)

      {:ok, {{_version, status, reason}, _headers, _body}} ->
        raise "DuckDB runtime download failed with #{status}: #{reason}"

      {:error, reason} ->
        raise "DuckDB runtime download failed: #{inspect(reason)}"
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

  defp install!(root, archive) do
    {:ok, entries} = :zip.extract(String.to_charlist(archive), [:memory])
    current = Path.join([root, ".runtime", "current"])
    File.rm_rf!(current)
    File.mkdir_p!(Path.join(current, "include"))
    File.mkdir_p!(Path.join(current, "lib"))

    copy_entry!(entries, "duckdb.h", Path.join([current, "include", "duckdb.h"]))

    entries
    |> Enum.filter(fn {name, _contents} ->
      Path.extname(List.to_string(name)) in [".so", ".dylib", ".dll", ".lib"]
    end)
    |> Enum.each(fn {name, contents} ->
      File.write!(Path.join([current, "lib", Path.basename(List.to_string(name))]), contents)
    end)
  end

  defp copy_entry!(entries, name, destination) do
    case Enum.find(entries, fn {entry, _contents} ->
           Path.basename(List.to_string(entry)) == name
         end) do
      {_entry, contents} -> File.write!(destination, contents)
      nil -> raise "DuckDB runtime archive is missing #{name}"
    end
  end

  defp sha256(contents) do
    :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
  end
end

Kinda.DuckDB.RuntimeFetcher.run()
