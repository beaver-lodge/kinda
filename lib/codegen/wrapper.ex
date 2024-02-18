defmodule Kinda.CodeGen.Wrapper do
  require Logger
  @moduledoc false
  defstruct types: [], functions: [], root_module: nil

  def new(root_module) do
    %__MODULE__{
      root_module: root_module
    }
  end

  defp dump_ast?() do
    System.get_env("KINDA_DUMP_AST") == "1"
  end

  defp run_zig(args, opts \\ []) do
    Logger.debug("[Kinda] zig #{Enum.join(args, " ")}")

    System.cmd(
      "zig",
      args,
      opts
    )
  end

  defp print_library_debug_info(dest_dir) do
    if System.get_env("KINDA_PRINT_LINKAGES") do
      for p <- dest_dir |> Path.join("**") |> Path.wildcard() do
        Logger.debug("[Kinda] [installed] #{p}")

        if Path.extname(p) in [".so"] do
          case :os.type() do
            {:unix, :darwin} ->
              {out, 0} = System.cmd("otool", ["-L", p])
              Logger.debug("[Kinda] #{out}")
              {out, 0} = System.cmd("otool", ["-l", p])

              String.split(out, "\n")
              |> Enum.filter(&String.contains?(String.downcase(&1), "rpath"))
              |> Enum.join("\n")
              |> Logger.debug()

            _ ->
              {out, 0} = System.cmd("ldd", [p])
              Logger.debug("[Kinda] #{out}")
              {out, 0} = System.cmd("readelf", ["-d", p])
              String.split(out, "\n") |> Enum.take(20) |> Enum.join("\n") |> Logger.debug()
          end
        end
      end
    end
  end

  # Generate Zig code from a header and build a Zig project to produce a NIF library
  def gen_and_build_zig(root_module, opts) do
    wrapper = Keyword.fetch!(opts, :wrapper)
    lib_name = Keyword.fetch!(opts, :lib_name)
    dest_dir = Keyword.fetch!(opts, :dest_dir)
    Logger.debug("[Kinda] generating Zig code for wrapper: #{wrapper}")
    translate_args = Keyword.get(opts, :translate_args, [])
    version = Keyword.fetch!(opts, :version)
    cache_root = Path.join([Mix.Project.app_path(), "zig_cache"])
    code_gen_module = Keyword.fetch!(opts, :code_gen_module)

    translate_out =
      with {out, 0} <-
             run_zig(["translate-c", wrapper, "--cache-dir", cache_root] ++ translate_args) do
        out
      else
        {_error, _} ->
          raise "fail to run zig translate-c for wrapper: #{wrapper}"
      end

    File.mkdir("tmp")

    translate_out_filename = "#{lib_name}.translate.out.zig"
    File.write!("tmp/#{translate_out_filename}.zig", translate_out)
    zig_ast = Zig.Parser.parse(translate_out).code

    task_dump_ast =
      Task.async(fn ->
        if dump_ast?() do
          File.write!(
            "tmp/#{translate_out_filename}.ex",
            zig_ast |> inspect(pretty: true, limit: :infinity)
          )
        end
      end)

    Logger.debug("[Kinda] generating Elixir code for wrapper: #{wrapper}")

    {:ok, target} = RustlerPrecompiled.target()
    lib_name = "#{lib_name}-v#{version}-#{target}"

    # zig will add the 'lib' prefix to the library name
    prefixed_lib_name = "lib#{lib_name}"

    print_library_debug_info(dest_dir)

    meta = %Kinda.Prebuilt.Meta{
      nifs: []
    }

    File.write!(
      Path.join(dest_dir, "kinda-meta-#{prefixed_lib_name}.ex"),
      inspect(meta, pretty: true, limit: :infinity)
    )

    if dump_ast?() do
      Task.await(task_dump_ast, :infinity)
    end

    {meta, %{dest_dir: dest_dir, lib_name: prefixed_lib_name}}
  end
end
