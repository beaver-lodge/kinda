defmodule Kinda.Testing.NativeScenario do
  @moduledoc """
  Runs serializable native-resource scenarios inside an isolated BEAM.

  Steps can bind call results, refer to earlier bindings, assert exact results,
  hot-upgrade NIF modules, purge old code, and request garbage collection. The
  data-only form can cross the port boundary used by `Kinda.Testing.Isolated`.
  """

  alias Kinda.Testing.NIFUpgrade

  @type resource_ref :: {:resource, atom()}
  @type native_call :: {module(), atom(), [term() | resource_ref()]}
  @type step ::
          {:call, atom(), native_call()}
          | {:call, native_call()}
          | {:expect, term(), native_call()}
          | {:upgrade, module(), atom(), String.t()}
          | {:purge, module()}
          | :garbage_collect

  @spec run([step()]) :: :ok
  def run(steps) when is_list(steps) do
    directory = scenario_directory!()

    try do
      run_steps(steps, %{}, directory)
    after
      File.rm_rf!(directory)
    end
  end

  defp run_steps([], _resources, _directory), do: :ok

  defp run_steps(
         [{:upgrade, module, application, library} | steps],
         resources,
         directory
       ) do
    snapshot = NIFUpgrade.remember!(module)
    nif_file = NIFUpgrade.copy_library!(application, library, directory)
    {:module, ^module, _binary, _load_result} = NIFUpgrade.load!(module, nif_file)

    try do
      run_steps(steps, resources, directory)
    after
      NIFUpgrade.restore!(snapshot)
    end
  end

  defp run_steps([step | steps], resources, directory) do
    resources = run_step(step, resources)
    run_steps(steps, resources, directory)
  end

  defp run_step({:call, name, call}, resources) do
    Map.put(resources, name, invoke(call, resources))
  end

  defp run_step({:call, call}, resources) do
    _result = invoke(call, resources)
    resources
  end

  defp run_step({:expect, expected, call}, resources) do
    actual = invoke(call, resources)

    if actual != expected do
      raise "native scenario expected #{inspect(expected)}, got: #{inspect(actual)}"
    end

    resources
  end

  defp run_step({:purge, module}, resources) do
    :code.purge(module)
    resources
  end

  defp run_step(:garbage_collect, resources) do
    :erlang.garbage_collect()
    resources
  end

  defp invoke({module, function, arguments}, resources) do
    apply(module, function, Enum.map(arguments, &resolve(&1, resources)))
  end

  defp resolve({:resource, name}, resources), do: Map.fetch!(resources, name)
  defp resolve(value, _resources), do: value

  defp scenario_directory! do
    directory =
      Path.join(
        System.tmp_dir!(),
        "kinda-native-scenario-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(directory)
    directory
  end
end
