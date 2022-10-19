defmodule Kinda.Prebuilt do
  require Logger

  defmacro __using__(opts) do
    quote do
      require Logger

      opts = unquote(opts)

      otp_app = Keyword.fetch!(opts, :otp_app)

      opts =
        Keyword.put_new(
          opts,
          :force_build,
          Application.compile_env(:kinda, [:force_build, otp_app])
        )

      case RustlerPrecompiled.__using__(__MODULE__, opts) do
        {:force_build, _only_rustler_opts} ->
          contents = Kinda.Prebuilt.__using__(__MODULE__, opts)
          Module.eval_quoted(__MODULE__, contents)

        {:ok, config} ->
          @on_load :load_rustler_precompiled
          @rustler_precompiled_load_from config.load_from
          @rustler_precompiled_load_data config.load_data

          {otp_app, path} = @rustler_precompiled_load_from

          load_path =
            otp_app
            |> Application.app_dir(path)

          {meta, _binding} =
            Path.dirname(load_path)
            |> Path.join("kinda-meta-#{Path.basename(load_path)}.ex")
            |> File.read!()
            |> Code.eval_string()

          contents = Kinda.Prebuilt.__using__(__MODULE__, Keyword.put(opts, :meta, meta))
          Module.eval_quoted(__MODULE__, contents)

          @doc false
          def load_rustler_precompiled do
            # Remove any old modules that may be loaded so we don't get
            # {:error, {:upgrade, 'Upgrade not supported by this NIF library.'}}
            :code.purge(__MODULE__)
            {otp_app, path} = @rustler_precompiled_load_from

            load_path =
              otp_app
              |> Application.app_dir(path)
              |> to_charlist()

            :erlang.load_nif(load_path, @rustler_precompiled_load_data)
          end

        {:error, precomp_error} when is_bitstring(precomp_error) ->
          precomp_error
          |> String.split("You can force the project to build from scratch with")
          |> List.first()
          |> String.trim()
          |> Kernel.<>("""

          You can force the project to build from scratch with:
              config :kinda, :force_build, #{otp_app}: true
          """)
          |> raise

        {:error, precomp_error} ->
          raise precomp_error
      end
    end
  end

  defp nif_ast(kinds, nifs, forward_module, zig_t_module_map) do
    # generate stubs for generated NIFs
    Logger.debug("[Kinda] generating NIF wrappers, forward_module: #{inspect(forward_module)}")

    extra_kind_nifs =
      kinds
      |> Enum.map(&Kinda.CodeGen.NIF.from_resource_kind/1)
      |> List.flatten()

    for nif <- nifs ++ extra_kind_nifs do
      args_ast = Macro.generate_unique_arguments(nif.arity, __MODULE__)

      %Kinda.CodeGen.NIF{wrapper_name: wrapper_name, nif_name: nif_name, ret: ret} = nif

      stub_ast =
        quote do
          @doc false
          def unquote(nif_name)(unquote_splicing(args_ast)),
            do:
              raise(
                "NIF for resource kind is not implemented, or failed to load NIF library. Function: :\"#{unquote(nif_name)}\"/#{unquote(nif.arity)}"
              )
        end

      wrapper_ast =
        if wrapper_name do
          if ret == "void" do
            quote do
              def unquote(String.to_atom(wrapper_name))(unquote_splicing(args_ast)) do
                refs = Kinda.unwrap_ref([unquote_splicing(args_ast)])
                ref = apply(__MODULE__, unquote(nif_name), refs)
                :ok = unquote(forward_module).check!(ref)
              end
            end
          else
            return_module = Kinda.module_name(ret, forward_module, zig_t_module_map)

            quote do
              def unquote(String.to_atom(wrapper_name))(unquote_splicing(args_ast)) do
                refs = Kinda.unwrap_ref([unquote_splicing(args_ast)])
                ref = apply(__MODULE__, unquote(nif_name), refs)

                struct!(unquote(return_module),
                  ref: unquote(forward_module).check!(ref)
                )
              end
            end
          end
        end

      [stub_ast, wrapper_ast]
    end
    |> List.flatten()
  end

  # generate resource modules
  defp kind_ast(root_module, forward_module, resource_kinds) do
    for %Kinda.CodeGen.Type{
          module_name: module_name,
          zig_t: zig_t,
          fields: fields
        } <-
          resource_kinds,
        Atom.to_string(module_name)
        |> String.starts_with?(Atom.to_string(root_module)) do
      Logger.debug("[Kinda] building resource kind #{module_name}")

      quote bind_quoted: [
              root_module: root_module,
              module_name: module_name,
              zig_t: zig_t,
              fields: fields,
              forward_module: forward_module
            ] do
        defmodule module_name do
          @moduledoc """
          #{zig_t}
          """

          use Kinda.ResourceKind,
            root_module: root_module,
            fields: fields,
            forward_module: forward_module
        end
      end
    end
  end

  defp load_ast(dest_dir, lib_name) do
    quote do
      # setup NIF loading
      @on_load :kinda_on_load
      @dest_dir unquote(dest_dir)
      def kinda_on_load do
        require Logger
        nif_path = Path.join(@dest_dir, "lib/#{unquote(lib_name)}")
        dylib = "#{nif_path}.dylib"
        so = "#{nif_path}.so"

        if File.exists?(dylib) do
          File.ln_s(dylib, so)
        end

        Logger.debug("[Kinda] loading NIF, path: #{nif_path}")

        with :ok <- :erlang.load_nif(nif_path, 0) do
          Logger.debug("[Kinda] NIF loaded, path: #{nif_path}")
          :ok
        else
          {:error, {:load_failed, msg}} when is_list(msg) ->
            Logger.error("[Kinda] NIF failed to load, path: #{nif_path}")
            Logger.error("[Kinda] #{msg}")

            :abort

          error ->
            Logger.error(
              "[Kinda] NIF failed to load, path: #{nif_path}, error: #{inspect(error)}"
            )

            :abort
        end
      end
    end
  end

  defp ast_from_meta(
         root_module,
         forward_module,
         kinds,
         %Kinda.Prebuilt.Meta{
           nifs: nifs,
           resource_kinds: resource_kinds,
           zig_t_module_map: zig_t_module_map
         }
       ) do
    kind_ast(root_module, forward_module, resource_kinds) ++
      nif_ast(kinds, nifs, forward_module, zig_t_module_map)
  end

  # A helper function to extract the logic from __using__ macro.
  @doc false
  def __using__(root_module, opts) do
    codegen_module = Keyword.fetch!(opts, :codegen_module)
    kinds = codegen_module.kinds()
    forward_module = Keyword.fetch!(opts, :forward_module)

    if opts[:force_build] do
      {meta, %{dest_dir: dest_dir, lib_name: lib_name}} = gen_and_build_zig(root_module, opts)
      ast_from_meta(root_module, forward_module, kinds, meta) ++ [load_ast(dest_dir, lib_name)]
    else
      meta = Keyword.fetch!(opts, :meta)
      ast_from_meta(root_module, forward_module, kinds, meta)
    end
  end

  alias Kinda.CodeGen.{Function, Type, Resource, NIF}

  defp primitive_types do
    ~w{
      bool
      c_int
      c_uint
      f32
      f64
      i16
      i32
      i64
      i8
      isize
      u16
      u32
      u64
      u8
      usize
    }
  end

  defp gen_kind_name_from_module_name(%Type{module_name: module_name, kind_name: nil} = t) do
    %{t | kind_name: Module.split(module_name) |> List.last()}
  end

  defp gen_kind_name_from_module_name(t), do: t

  defp gen_nif_name_from_module_name(
         module_name,
         %NIF{wrapper_name: wrapper_name, nif_name: nil} = nif
       ) do
    %{nif | nif_name: Module.concat(module_name, wrapper_name)}
  end

  defp gen_nif_name_from_module_name(_module_name, f), do: f

  # Generate Zig code from a header and build a Zig project to produce a NIF library
  defp gen_and_build_zig(root_module, opts) do
    wrapper = Keyword.fetch!(opts, :wrapper)
    lib_name = Keyword.fetch!(opts, :lib_name)
    dest_dir = Keyword.fetch!(opts, :dest_dir)
    project_dir = Keyword.fetch!(opts, :zig_src)
    project_dir = Path.join(project_dir, "proj")
    source_dir = Path.join(project_dir, "src")
    project_dir = Path.join(project_dir, Atom.to_string(Mix.env()))
    project_source_dir = Path.join(project_dir, "src")
    Logger.debug("[Kinda] generating Zig code for wrapper: #{wrapper}")
    include_paths = Keyword.get(opts, :include_paths, %{})
    constants = Keyword.get(opts, :constants, %{})
    version = Keyword.fetch!(opts, :version)
    cache_root = Path.join([Mix.Project.build_path(), "mlir-zig-build", "zig-cache"])
    codegen_module = Keyword.fetch!(opts, :codegen_module)

    if not is_map(include_paths) do
      raise "include_paths must be a map so that we could generate variables for build.zig. Got: #{inspect(include_paths)}"
    end

    if not is_map(constants) do
      raise "constants must be a map so that we could generate variables for build.zig. Got: #{inspect(constants)}"
    end

    include_path_args =
      for {_, path} <- include_paths do
        ["-I", path]
      end
      |> List.flatten()

    out =
      with {out, 0} <-
             System.cmd(
               "zig",
               ["translate-c", wrapper, "--cache-dir", cache_root] ++ include_path_args
             ) do
        out
      else
        {_error, _} ->
          raise "fail to run zig translate-c for wrapper: #{wrapper}"
      end

    functions =
      String.split(out, "\n", trim: true)
      |> Enum.filter(fn x -> String.contains?(x, "extern") and String.contains?(x, "fn") end)
      |> codegen_module.filter_functions()

    # collecting functions with zig translate
    prints =
      for f <- functions do
        "pub extern fn " <> name = f
        name = name |> String.split("(") |> Enum.at(0)

        """
        {
        @setEvalBranchQuota(10000);
        const func_type = @typeInfo(@TypeOf(c.#{name}));
        comptime var i = 0;
        if (func_type.Fn.calling_convention == .C) {
          print("func: #{name}\\n", .{});
          inline while (i < func_type.Fn.args.len) : (i += 1) {
            const arg_type = func_type.Fn.args[i];
            if (arg_type.arg_type) |t| {
              print("arg: {s}\\n", .{ @typeName(t) });
            } else {
              unreachable;
            }
          }
          print("ret: {}\\n", .{ func_type.Fn.return_type });
        }
        }
        """
      end

    source = """
    const expect = @import("std").testing.expect;
    const print = @import("std").debug.print;
    const c = @cImport({
        @cDefine("_NO_CRT_STDIO_INLINE", "1");
        @cInclude("#{wrapper}");
    });
    pub fn main() !void {
        #{Enum.join(prints, "\n")}
    }
    """

    File.mkdir("tmp")
    dst = "tmp/print_arity.zig"
    File.write!(dst, source)

    out =
      with {out, 0} <-
             System.cmd("zig", ["run", dst, "--cache-dir", cache_root] ++ include_path_args,
               stderr_to_stdout: true
             ) do
        File.write!("#{dst}.out.txt", out)
        out
      else
        {error, ret_code} ->
          Logger.error("[Zig] #{error}")
          raise "fail to run reflection, ret_code: #{ret_code}"
      end

    functions =
      out
      |> String.trim()
      |> String.split("\n", trim: true)
      |> Enum.reduce([], fn
        "func: " <> func, acc ->
          [%Function{name: func} | acc]

        "arg: " <> arg, [%Function{args: args} = f | tail] ->
          [%{f | args: args ++ [Function.process_type(arg)]} | tail]

        "ret: " <> ret, [%Function{ret: nil} = f | tail] ->
          [%{f | ret: Function.process_type(ret)} | tail]
      end)

    types =
      Enum.map(functions, fn f -> [f.ret, f.args] end)
      |> List.flatten()

    extra = primitive_types() |> Enum.map(&Type.ptr_type_name/1)

    types = Enum.sort(types ++ extra) |> Enum.uniq()

    resource_kinds =
      types
      |> Enum.reject(fn x -> String.starts_with?(x, "[*c]") end)
      |> Enum.reject(fn x -> x in ["void"] end)
      |> Enum.map(fn x ->
        # TODO: support skip
        {:ok, t} = codegen_module.type_gen(root_module, x)
        t |> gen_kind_name_from_module_name
      end)

    resource_kind_map =
      resource_kinds
      |> Enum.map(fn %{zig_t: zig_t, kind_name: kind_name} -> {zig_t, kind_name} end)
      |> Map.new()

    zig_t_module_map =
      resource_kinds
      |> Enum.map(fn %{zig_t: zig_t, module_name: module_name} -> {zig_t, module_name} end)
      |> Map.new()

    # generate wrapper.imp.zig source
    source =
      for %Function{name: name, args: args, ret: ret} <- functions do
        proxy_arg_uses =
          for {_arg, i} <- Enum.with_index(args) do
            "arg#{i}"
          end

        arg_vars =
          for {arg, i} <- Enum.with_index(args) do
            """
              var arg#{i}: #{Resource.resource_type_struct(arg, resource_kind_map)}.T = #{Resource.resource_type_resource_kind(arg, resource_kind_map)}.fetch(env, args[#{i}])
              catch
              return beam.make_error_binary(env, "fail to fetch resource for argument ##{i}, expected: " ++ @typeName(#{Resource.resource_type_struct(arg, resource_kind_map)}.T));
            """
          end

        body =
          if ret == "void" do
            """
            #{Enum.join(arg_vars, "")}
            c.#{name}(#{Enum.join(proxy_arg_uses, ", ")});
            return beam.make_ok(env);
            """
          else
            """
            #{Enum.join(arg_vars, "")}
            return #{Resource.resource_type_resource_kind(ret, resource_kind_map)}.make(env, c.#{name}(#{Enum.join(proxy_arg_uses, ", ")}))
            catch return beam.make_error_binary(env, "fail to make resource for: " ++ @typeName(#{Resource.resource_type_struct(ret, resource_kind_map)}.T));
            """
          end

        """
        fn #{name}(env: beam.env, _: c_int, #{if length(args) == 0, do: "_", else: "args"}: [*c] const beam.term) callconv(.C) beam.term {
          #{body}
        }
        """
      end
      |> Enum.join("\n")

    resource_kinds_str =
      resource_kinds
      |> Enum.map(&Type.gen_resource_kind/1)
      |> Enum.join()

    resource_kinds_str_open_str =
      resource_kinds
      |> Enum.map(&Resource.resource_open/1)
      |> Enum.join()

    source = resource_kinds_str <> source

    nifs =
      Enum.map(functions, fn x -> codegen_module.nif_gen(x) end)
      |> Enum.map(&gen_nif_name_from_module_name(root_module, &1))
      |> Enum.concat(List.flatten(Enum.map(resource_kinds, &NIF.from_resource_kind/1)))

    # TODO: reverse the alias here
    source = """
    #{source}
    pub fn open_generated_resource_types(env: beam.env) void {
    #{resource_kinds_str_open_str}
    }
    pub export const generated_nifs = .{
      #{nifs |> Enum.map(&Kinda.CodeGen.NIF.gen/1) |> Enum.join("  ")}
    }
    #{if length(resource_kinds) > 0, do: "++", else: ""}
    #{Enum.map(resource_kinds, fn %{kind_name: kind_name} -> "#{kind_name}.nifs" end) |> Enum.join(" ++ \n")};
    """

    source =
      """
      pub const c = @cImport({
        @cDefine("_NO_CRT_STDIO_INLINE", "1");
        @cInclude("#{wrapper}");
      });
      const beam = @import("beam.zig");
      const kinda = @import("kinda.zig");
      const e = @import("erl_nif.zig");
      pub const root_module = "#{root_module}";
      """ <> source

    dst = Path.join(project_source_dir, "#{lib_name}.imp.zig")
    File.mkdir_p(project_source_dir)
    Logger.debug("[Kinda] writing source import to: #{dst}")
    File.write!(dst, source)

    # generate build.inc.zig source
    build_source =
      for {name, path} <- include_paths do
        """
        pub const #{name} = "#{path}";
        """
      end
      |> Enum.join()

    build_source =
      for {name, path} <- constants do
        """
        pub const #{name} = "#{path}";
        """
      end
      |> Enum.join()
      |> Kernel.<>(build_source)

    erts_include =
      Path.join([
        List.to_string(:code.root_dir()),
        "erts-#{:erlang.system_info(:version)}",
        "include"
      ])

    {:ok, target} = RustlerPrecompiled.target()
    lib_name = "#{lib_name}-v#{version}-#{target}"

    build_source =
      build_source <>
        """
        pub const cache_root = "#{cache_root}";
        pub const erts_include = "#{erts_include}";
        pub const lib_name = "#{lib_name}";
        """

    # zig will add the 'lib' prefix to the library name
    lib_name = "lib#{lib_name}"

    dst = Path.join(project_dir, "build.imp.zig")
    Logger.debug("[Kinda] writing build import to: #{dst}")
    File.write!(dst, build_source)

    if Mix.env() in [:test, :dev] do
      with {_, 0} <- System.cmd("zig", ["fmt", "."], cd: project_dir) do
        :ok
      else
        {_error, _} ->
          Logger.warn("fail to run zig fmt")
      end
    end

    sym_src_dir = Path.join(project_dir, "src")
    File.mkdir_p(sym_src_dir)

    zig_sources =
      Kinda.zig_sources() ++
        Path.wildcard(Path.join(source_dir, "*.zig"))

    for zig_source <- zig_sources do
      zig_source_link = Path.join(sym_src_dir, Path.basename(zig_source))
      Logger.debug("[Kinda] sym linking source #{zig_source} => #{zig_source_link}")

      if File.exists?(zig_source_link) do
        File.rm(zig_source_link)
      end

      File.ln_s(zig_source, zig_source_link)
    end

    Logger.debug("[Kinda] building Zig project in: #{project_dir}")

    with {_, 0} <- System.cmd("zig", ["build", "--prefix", dest_dir], cd: project_dir) do
      Logger.debug("[Kinda] Zig library installed to: #{dest_dir}")
      :ok
    else
      {_error, ret_code} ->
        raise "fail to run zig compiler, ret_code: #{ret_code}"
    end

    for p <- dest_dir |> Path.join("**") |> Path.wildcard() do
      Logger.debug("[Kinda] [installed] #{p}")
    end

    meta = %Kinda.Prebuilt.Meta{
      nifs: nifs,
      resource_kinds: resource_kinds,
      zig_t_module_map: zig_t_module_map
    }

    File.write!(
      Path.join(dest_dir, "kinda-meta-#{lib_name}.ex"),
      inspect(meta, pretty: true, limit: :infinity)
    )

    {meta, %{dest_dir: dest_dir, lib_name: lib_name}}
  end
end
