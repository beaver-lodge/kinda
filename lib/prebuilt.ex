defmodule Kinda.Prebuilt do
  require Logger
  alias Kinda.CodeGen.{NIFDecl, Wrapper}

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

  defp nif_ast(kinds, nifs, forward_module) do
    # generate stubs for generated NIFs
    Logger.debug("[Kinda] generating NIF wrappers, forward_module: #{inspect(forward_module)}")

    extra_kind_nifs =
      kinds
      |> Enum.map(&NIFDecl.from_resource_kind/1)
      |> List.flatten()

    for nif <- nifs ++ extra_kind_nifs do
      args_ast = Macro.generate_unique_arguments(nif.arity, __MODULE__)

      %NIFDecl{wrapper_name: wrapper_name, nif_name: nif_name} = nif

      wrapper_name =
        if is_bitstring(wrapper_name) do
          String.to_atom(wrapper_name)
        else
          wrapper_name
        end

      quote do
        @doc false
        def unquote(nif_name)(unquote_splicing(args_ast)),
          do:
            raise(
              "NIF for resource kind is not implemented, or failed to load NIF library. Function: :\"#{unquote(nif_name)}\"/#{unquote(nif.arity)}"
            )

        def unquote(wrapper_name)(unquote_splicing(args_ast)) do
          refs = Kinda.unwrap_ref([unquote_splicing(args_ast)])
          ret = apply(__MODULE__, unquote(nif_name), refs)
          unquote(forward_module).check!(ret)
        end
      end
    end
    |> List.flatten()
  end

  # generate resource modules

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
         forward_module,
         kinds,
         %Kinda.Prebuilt.Meta{
           nifs: nifs
         }
       ) do
    nif_ast(kinds, nifs, forward_module)
  end

  # A helper function to extract the logic from __using__ macro.
  @doc false
  def __using__(root_module, opts) do
    code_gen_module = Keyword.fetch!(opts, :code_gen_module)
    kinds = code_gen_module.kinds()
    forward_module = Keyword.fetch!(opts, :forward_module)

    if opts[:force_build] do
      {meta, %{dest_dir: dest_dir, lib_name: lib_name}} =
        Wrapper.gen_and_build_zig(root_module, opts)

      ast_from_meta(forward_module, kinds, meta) ++ [load_ast(dest_dir, lib_name)]
    else
      meta = Keyword.fetch!(opts, :meta)
      ast_from_meta(forward_module, kinds, meta)
    end
  end
end
