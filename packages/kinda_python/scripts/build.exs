defmodule Kinda.Python.Build do
  @moduledoc false

  def run([cache, prefix, erts_include]) do
    python = System.find_executable("python3") || System.find_executable("python")

    if is_nil(python) do
      raise "CPython 3.14 executable not found; set PATH before compiling kinda_python"
    end

    version =
      query!(python, "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

    unless version == "3.14" do
      raise "kinda_python requires CPython 3.14, found #{version}"
    end

    include = query!(python, "import sysconfig; print(sysconfig.get_config_var('INCLUDEPY'))")
    ld_library = query!(python, "import sysconfig; print(sysconfig.get_config_var('LDLIBRARY'))")
    library_path = find_runtime_library!(python, ld_library)

    args = [
      "build",
      "--cache-dir",
      cache,
      "--prefix",
      prefix,
      "--search-prefix",
      Path.dirname(erts_include),
      "-Dpython-include=#{include}",
      "-Dpython-library-path=#{library_path}",
      "-freference-trace"
    ]

    {output, status} = System.cmd("zig", args, stderr_to_stdout: true)
    IO.write(output)

    if status != 0, do: System.halt(status)
  end

  defp query!(python, expression) do
    case System.cmd(python, ["-c", expression], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "CPython configuration query failed (#{status}): #{output}"
    end
  end

  defp find_runtime_library!(python, ld_library) do
    candidates =
      query!(
        python,
        """
        import os, sys, sysconfig
        version = sysconfig.get_config_var('VERSION')
        framework = sysconfig.get_config_var('PYTHONFRAMEWORK')
        framework_prefix = sysconfig.get_config_var('PYTHONFRAMEWORKPREFIX')
        framework_dir = sysconfig.get_config_var('PYTHONFRAMEWORKDIR')
        suffix = 't' if sysconfig.get_config_var('Py_GIL_DISABLED') else ''
        candidates = [
          os.path.join(sys.base_prefix, 'libs', f'python{sys.version_info.major}{sys.version_info.minor}{suffix}.lib'),
          os.path.join(sysconfig.get_config_var('LIBDIR') or '', sysconfig.get_config_var('LDLIBRARY') or ''),
          os.path.join(sysconfig.get_config_var('LIBDIR') or '', sysconfig.get_config_var('INSTSONAME') or ''),
          os.path.join(framework_prefix or '', framework_dir or '', 'Versions', version or '', framework or ''),
        ]
        print('\\n'.join(candidates))
        """
      )
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)

    case Enum.find(candidates, &File.exists?/1) do
      nil ->
        raise "CPython runtime library #{ld_library} was not found; checked #{inspect(candidates)}"

      source ->
        source
    end
  end
end

Kinda.Python.Build.run(System.argv())
