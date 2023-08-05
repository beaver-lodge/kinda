defmodule Kinda.CodeGen.Wrapper do
  require Logger
  @moduledoc false
  defstruct types: [], functions: [], root_module: nil

  alias Kinda.CodeGen.{KindDecl, Resource, NIFDecl}

  def new(root_module) do
    %__MODULE__{
      root_module: root_module
    }
  end

  defp dump_ast?() do
    System.get_env("KINDA_DUMP_AST") == "1"
  end

  defp put_types(%__MODULE__{} = w, zig_ast) when is_list(zig_ast) do
    functions =
      for {:fn, %Zig.Parser.FnOptions{extern: true, inline: inline}, _parts} = f <-
            zig_ast,
          inline != true do
        f
      end

    func_types =
      Enum.reduce(functions, [], fn {:fn, _opts, parts}, acc ->
        params =
          for {_name, _opts, t} <- parts[:params] || [] do
            t
          end

        return_type = parts[:type]
        [return_type | params] ++ acc
      end)

    primitive_ptr_types = KindDecl.primitive_types() |> Enum.map(&KindDecl.ptr_type_name/1)
    primitive_array_types = KindDecl.primitive_types() |> Enum.map(&KindDecl.array_type_name/1)
    primitive_types = KindDecl.primitive_types() ++ primitive_ptr_types ++ primitive_array_types
    types = (func_types ++ primitive_types) |> Enum.uniq()
    %__MODULE__{w | functions: functions, types: types}
  end

  # if kind_name is absent, generate it from last part of module_name
  defp gen_kind_name_from_module_name(%KindDecl{module_name: module_name, kind_name: nil} = t) do
    %{t | kind_name: Module.split(module_name) |> List.last()}
  end

  defp gen_kind_name_from_module_name(t), do: t

  defp gen_nif_name_from_module_name(
         module_name,
         %NIFDecl{wrapper_name: wrapper_name, nif_name: nil} = nif
       ) do
    %{nif | nif_name: Module.concat(module_name, wrapper_name)}
  end

  defp gen_nif_name_from_module_name(_module_name, f), do: f

  defp collect_types(zig_ast) when is_list(zig_ast) do
    functions =
      for {:fn, %Zig.Parser.FnOptions{extern: true, inline: inline}, _parts} = f <-
            zig_ast,
          inline != true do
        f
      end

    Enum.reduce(functions, MapSet.new(), fn {:fn, _opts, parts}, acc ->
      params =
        for {_name, _opts, t} <- parts[:params] || [] do
          t
        end

      return_type = parts[:type]

      for t <- [return_type | params], t not in [:void] do
        with {:ok, t} <- Kinda.ZigAST.extract_item_type(t) do
          t
        else
          _ -> t
        end
      end
      |> MapSet.new()
      |> MapSet.union(acc)
    end)
  end

  defp fmt_zig_project(project_dir) do
    Logger.debug("[Kinda] formatting zig project: #{project_dir}")

    if Mix.env() in [:test, :dev] do
      with {_, 0} <- System.cmd("zig", ["fmt", "."], cd: project_dir) do
        :ok
      else
        {_error, _} ->
          Logger.warning("fail to run zig fmt")
      end
    end
  end

  defp run_zig(args, opts \\ []) do
    Logger.debug("[Kinda] zig #{Enum.join(args, " ")}")

    System.cmd(
      "zig",
      args,
      opts
    )
  end

  # Generate Zig code from a header and build a Zig project to produce a NIF library
  def gen_and_build_zig(root_module, opts) do
    wrapper = Keyword.fetch!(opts, :wrapper)
    lib_name = Keyword.fetch!(opts, :lib_name)
    dest_dir = Keyword.fetch!(opts, :dest_dir)
    source_dir = Keyword.fetch!(opts, :zig_src)
    project_dir = Keyword.fetch!(opts, :zig_proj)
    project_dir = Path.join(project_dir, Atom.to_string(Mix.env()))
    project_source_dir = Path.join(project_dir, "src")
    Logger.debug("[Kinda] generating Zig code for wrapper: #{wrapper}")
    translate_args = Keyword.get(opts, :translate_args, %{})
    build_args = Keyword.get(opts, :build_args, %{})
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

    # collecting functions with zig translate
    used_types = collect_types(zig_ast)

    type_constants =
      for {:const,
           %Zig.Parser.ConstOptions{
             pub: true,
             comptime: false
           }, {const_name, nil, v}} <- zig_ast do
        {const_name, v}
      end
      |> Map.new()

    w = new(root_module) |> put_types(zig_ast)
    functions = w.functions
    types = w.types

    resource_kinds =
      types
      |> Enum.reject(fn
        {:cptr, _, _} -> true
        _ -> false
      end)
      |> Enum.reject(fn x -> x in [:void] end)
      |> Enum.map(fn x ->
        with {:ok, t} <- code_gen_module.type_gen(root_module, x) do
          gen_kind_name_from_module_name(t)
        else
          :skip -> nil
        end
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
      for {:fn, _, parts} <- functions do
        [name: name, params: params, type: ret] = parts

        param_types =
          for {{name, _, t}, i} <- Enum.with_index(params) do
            case name do
              :_ ->
                {"arg\##{i}", t}

              _ ->
                {name, t}
            end
          end

        for {arg_name, t} <- [{"return", ret} | param_types], t not in [:void] do
          t =
            with {:ok, t} <- Kinda.ZigAST.extract_item_type(t) do
              t
            else
              _ -> t
            end

          if t not in used_types do
            raise "type #{inspect(t)} is not used in wrapper: #{wrapper}"
          end

          if not (Map.has_key?(type_constants, t) or Map.has_key?(zig_t_module_map, t) or
                    KindDecl.is_primitive_type?(t) or
                    KindDecl.is_opaque_ptr?(t)) do
            Logger.error(
              "in function: #{name}, #{arg_name}'s type is not resolved, consider adding a typedef in the wrapper header. Zig ast:\n #{inspect(t, pretty: true)}"
            )

            raise "type not resolved"
          end
        end

        error_prefix_when_calling = "when calling C function #{name}"

        {arg_vars, arg_uses} =
          for {{arg_name, _t_opts, t}, i} <- Enum.with_index(params) do
            arg_var_name =
              case arg_name do
                :_ ->
                  "arg_#{i}"

                :args ->
                  "arg_#{i}"

                _ ->
                  if Kinda.ZigAST.is_keyword?(arg_name) do
                    "#{arg_name}_"
                  else
                    arg_name
                  end
              end

            resource_type_struct = Resource.resource_type_struct(t, resource_kind_map)

            arg_var = """
            var #{arg_var_name}: #{resource_type_struct}.T = #{Resource.resource_type_resource_kind(t, resource_kind_map)}.fetch(env, args[#{i}])
            catch
            return beam.make_error_binary(env, "#{error_prefix_when_calling}, fail to fetch resource for #{arg_var_name}, expected: " ++ @typeName(#{resource_type_struct}.T));
            """

            {arg_var, arg_var_name}
          end
          |> Enum.reduce({[], []}, fn {arg_var, arg_use}, {arg_vars, arg_uses} ->
            {arg_vars ++ [arg_var], arg_uses ++ [arg_use]}
          end)

        body =
          if ret == :void do
            """
            #{Enum.join(arg_vars, "")}
            c.#{name}(#{Enum.join(arg_uses, ", ")});
            return beam.make_ok(env);
            """
          else
            """
            #{Enum.join(arg_vars, "")}
            return #{Resource.resource_type_resource_kind(ret, resource_kind_map)}.make(env, c.#{name}(#{Enum.join(arg_uses, ", ")}))
            catch return beam.make_error_binary(env, "#{error_prefix_when_calling}, fail to make resource for: " ++ @typeName(#{Resource.resource_type_struct(ret, resource_kind_map)}.T));
            """
          end

        len_params =
          case params do
            [:...] ->
              0

            _ ->
              length(params)
          end

        """
        fn #{name}(env: beam.env, _: c_int, #{if len_params == 0, do: "_", else: "args"}: [*c] const beam.term) callconv(.C) beam.term {
          #{body}
        }
        """
      end
      |> Enum.join("\n")

    resource_kinds_str =
      resource_kinds
      |> Enum.map(fn k -> KindDecl.gen_resource_kind(k) end)
      |> Enum.join()

    resource_kinds_str_open_str =
      resource_kinds
      |> Enum.map(&Resource.resource_open/1)
      |> Enum.join()

    source = resource_kinds_str <> source

    nifs =
      Enum.map(functions, fn x -> code_gen_module.nif_gen(x) end)
      |> Enum.map(&gen_nif_name_from_module_name(root_module, &1))
      |> Enum.concat(List.flatten(Enum.map(resource_kinds, &NIFDecl.from_resource_kind/1)))

    # TODO: reverse the alias here
    source = """
    #{source}
    pub fn open_generated_resource_types(env: beam.env) void {
    #{resource_kinds_str_open_str}
    }
    pub const generated_nifs = .{
      #{nifs |> Enum.map(&Kinda.CodeGen.NIFDecl.gen/1) |> Enum.join("  ")}
    }
    #{if length(resource_kinds) > 0, do: "++", else: ""}
    #{Enum.map(resource_kinds, fn %{kind_name: kind_name} -> "#{kind_name}.nifs" end) |> Enum.join(" ++ \n")};
    """

    source =
      """
      pub const c = @import("prelude.zig");
      const beam = @import("beam.zig");
      const kinda = @import("kinda.zig");
      const e = @import("erl_nif.zig");
      pub const root_module = "#{root_module}";
      """ <> source

    dst = Path.join(project_source_dir, "#{lib_name}.imp.zig")
    File.mkdir_p(project_source_dir)
    Logger.debug("[Kinda] writing source import to: #{dst}")
    File.write!(dst, source)

    erts_include =
      Path.join([
        List.to_string(:code.root_dir()),
        "erts-#{:erlang.system_info(:version)}"
      ])

    {:ok, target} = RustlerPrecompiled.target()
    lib_name = "#{lib_name}-v#{version}-#{target}"

    # zig will add the 'lib' prefix to the library name
    prefixed_lib_name = "lib#{lib_name}"
    fmt_zig_project(project_dir)

    zig_sources =
      Kinda.zig_sources() ++
        Path.wildcard(Path.join(source_dir, "*.zig"))

    File.mkdir_p(project_source_dir)

    for zig_source <- zig_sources do
      zig_source = zig_source |> Path.absname()
      zig_source_link = Path.join(project_source_dir, Path.basename(zig_source)) |> Path.absname()
      Logger.debug("[Kinda] sym linking source #{zig_source} => #{zig_source_link}")

      if File.exists?(zig_source_link) do
        File.rm(zig_source_link)
      end

      File.ln_s(zig_source, zig_source_link)
    end

    Logger.debug("[Kinda] building Zig project in: #{project_dir}")

    with {_, 0} <-
           run_zig(
             ["build", "--prefix", dest_dir, "-freference-trace", "--cache-dir", cache_root] ++
               build_args ++ ["--search-prefix", erts_include, "-DKINDA_LIB_NAME=#{lib_name}"],
             cd: project_dir,
             stderr_to_stdout: true,
             env: [{"KINDA_LIB_NAME", lib_name}]
           ) do
      Logger.debug("[Kinda] Zig library installed to: #{dest_dir}")
      :ok
    else
      {error, ret_code} ->
        Logger.error(error)
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
      Path.join(dest_dir, "kinda-meta-#{prefixed_lib_name}.ex"),
      inspect(meta, pretty: true, limit: :infinity)
    )

    if dump_ast?() do
      Task.await(task_dump_ast, :infinity)
    end

    {meta, %{dest_dir: dest_dir, lib_name: prefixed_lib_name}}
  end
end
