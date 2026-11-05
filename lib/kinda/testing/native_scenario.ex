defmodule Kinda.Testing.NativeScenario do
  @moduledoc """
  Runs serializable native-resource scenarios inside an isolated BEAM.

  Steps can bind and drop call results, refer to earlier bindings, assert exact
  or eventually-observed results, hot-upgrade NIF modules, purge old code, and
  request garbage collection. The data-only form can cross the port boundary
  used by `Kinda.Testing.Isolated`.
  """

  alias Kinda.Testing.NIFUpgrade

  @type resource_ref :: {:resource, atom()}
  @type native_call :: {module(), atom(), [term() | resource_ref()]}
  @type step ::
          {:call, atom(), native_call()}
          | {:call, native_call()}
          | {:drop, atom()}
          | {:expect, term(), native_call()}
          | {:eventually_expect, term(), native_call()}
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

  defp run_steps([{:upgrade, module, application, library} | steps], resources, directory) do
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

  defp run_step({:call, name, call}, resources), do: Map.put(resources, name, invoke(call, resources))

  defp run_step({:drop, name}, resources), do: Map.delete(resources, name)

  defp run_step(step, resources) do
    case step do
      {:call, call} -> invoke(call, resources)
      {:expect, expected, call} -> expect!(expected, invoke(call, resources))
      {:eventually_expect, expected, call} -> eventually_expect(expected, call, resources, 100)
      {:purge, module} -> :code.purge(module)
      :garbage_collect -> :erlang.garbage_collect()
    end

    resources
  end

  defp expect!(expected, actual) when expected == actual, do: :ok
  defp expect!(expected, actual), do: expectation_failed(expected, actual)

  defp expectation_failed(expected, actual),
    do: raise("native scenario expected #{inspect(expected)}, got: #{inspect(actual)}")

  defp invoke({module, function, arguments}, resources),
    do: apply(module, function, Enum.map(arguments, &resolve(&1, resources)))

  defp resolve({:resource, name}, resources), do: Map.fetch!(resources, name)
  defp resolve(value, _resources), do: value

  defp eventually_expect(expected, call, resources, attempts) when attempts > 0 do
    case invoke(call, resources) do
      ^expected ->
        :ok

      _actual ->
        :erlang.garbage_collect()
        Process.sleep(10)
        eventually_expect(expected, call, resources, attempts - 1)
    end
  end

  defp eventually_expect(expected, call, resources, 0), do: expectation_failed(expected, invoke(call, resources))

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
