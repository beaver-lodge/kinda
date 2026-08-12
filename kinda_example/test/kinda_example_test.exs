defmodule KindaExampleTest do
  use ExUnit.Case

  alias KindaExample.{NIF, Native}
  alias KindaExample.NIF.Raw

  test "add in c" do
    assert 3 ==
             NIF.kinda_example_add(1, 2) |> Native.to_term()

    error = catch_error(NIF.kinda_example_add(1, "2"))

    assert %Kinda.CallError{
             message: "Fail to fetch argument #2",
             reason: :argument_decode_failed,
             phase: :argument_decode,
             function: :kinda_example_add,
             arity: 2,
             argument_index: 2,
             argument_name: :rhs,
             expected: "c_int",
             actual: "binary",
             native_error: "Function clause error"
           } = error

    assert Exception.message(error) ==
             "kinda_example_add/2 rejected argument #2 (rhs): expected c_int, got binary"
  end

  test "argument diagnostics have no fixed arity limit" do
    arguments = List.duplicate(1, 18) ++ ["19"]
    error = catch_error(apply(NIF, :kinda_example_sum_19, arguments))

    assert %Kinda.CallError{
             phase: :argument_decode,
             function: :kinda_example_sum_19,
             arity: 19,
             argument_index: 19,
             argument_name: :value_19,
             expected: "c_int",
             actual: "binary"
           } = error

    assert Exception.message(error) =~ "argument #19 (value_19)"
  end

  test "custom make" do
    assert 100 ==
             NIF.CInt.make(100)
             |> Native.to_term()

    e = catch_error(NIF.Raw."Elixir.KindaExample.NIF.StrInt.make"(1))
    assert Exception.message(e) =~ "Function clause error\n"

    err = catch_error(NIF.Raw."Elixir.KindaExample.NIF.StrInt.make"(1))
    # only test this on macOS, it will crash on Linux
    txt = Exception.message(err)

    assert txt =~ "to print the native error return trace, set KINDA_DUMP_STACK_TRACE=1"

    assert match?(%Kinda.CallError{message: "Function clause error"}, err)

    assert 1 ==
             NIF.Raw."Elixir.KindaExample.NIF.StrInt.make"("1")
             |> NIF.Raw."Elixir.KindaExample.NIF.CInt.primitive"()

    %NIF.StrInt{ref: ref} = NIF.StrInt.make("1")
    assert 1 == ref |> NIF.Raw."Elixir.KindaExample.NIF.CInt.primitive"()
  end

  test "resource helpers release native references and run destructors after GC" do
    baseline = Raw.lifecycle_fixture_stats()
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        value = Raw.lifecycle_fixture_make_value(42)

        resources = [
          value,
          Raw.lifecycle_fixture_make_pointer(value),
          Raw.lifecycle_fixture_make_list_array([1, 2, 3]),
          Raw.lifecycle_fixture_make_binary_array(<<1, 2, 3, 4>>)
        ]

        send(parent, {:resources_created, self()})

        receive do
          :release_resources -> send(parent, {:resources_released, length(resources)})
        end
      end)

    assert_receive {:resources_created, ^owner}
    send(owner, :release_resources)
    assert_receive {:resources_released, 4}
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}

    assert_eventually(fn ->
      lifecycle_counts_reached?(Raw.lifecycle_fixture_stats(), baseline, {1, 1, 1, 1})
    end)
  end

  test "partially initialized resources release their native references on error" do
    baseline = Raw.lifecycle_fixture_stats()

    assert %Kinda.CallError{} =
             catch_error(Raw.lifecycle_fixture_make_list_array([1, :not_an_integer]))

    assert %Kinda.CallError{} = catch_error(Raw.lifecycle_fixture_make_pointer(:not_a_resource))

    assert_eventually(fn ->
      lifecycle_counts_reached?(Raw.lifecycle_fixture_stats(), baseline, {0, 1, 1, 0})
    end)
  end

  test "callback fixture rejects scheduler calls and projects worker return values" do
    callback = fn handle, range ->
      assert {:kind, KindaExample.NIF.CallbackHandle, handle_ref} = handle
      assert is_reference(handle_ref)
      assert 3 = length(range)
      assert Enum.all?(range, &match?({:kind, KindaExample.NIF.CallbackHandle, _}, &1))
      {:ok, {7, 70}}
    end

    registration = Raw.callback_fixture_register(callback, nil, 1_000)

    assert :CallbackOnSchedulerThread =
             Raw.callback_fixture_invoke_on_scheduler(registration, 5)

    assert :ok = Raw.callback_fixture_invoke_on_worker(registration, 5)

    assert_receive {:invoke, token, ^callback, _id, handle, range}

    assert {:ok, {7, 70}} =
             Kinda.CallbackRuntime.invoke_reply(
               token,
               fn -> callback.(handle, range) end,
               &reply_projection/2
             )

    assert_receive {:callback_fixture_done, :replied, true, 7, 70}
  end

  test "callback fixture bounds waits and rejects late replies" do
    callback = fn _handle, _range -> {:ok, {1, 2}} end
    registration = Raw.callback_fixture_register(callback, nil, 20)

    assert :ok = Raw.callback_fixture_invoke_on_worker(registration, 1)
    assert_receive {:invoke, token, ^callback, _id, _handle, _range}
    assert_receive {:callback_fixture_done, :timed_out, false, 0, 0}, 1_000
    assert :stale = Raw.callback_fixture_reply_code(token, true, 9)
  end

  test "callback fixture supports cancellation" do
    callback = fn _handle, _range -> {:ok, {1, 2}} end
    registration = Raw.callback_fixture_register(callback, nil, 1_000)

    assert :ok = Raw.callback_fixture_invoke_on_worker(registration, 1)
    assert_receive {:invoke, token, ^callback, _id, _handle, _range}
    assert :ok = Raw.callback_fixture_cancel(token)
    assert_receive {:callback_fixture_done, :canceled, false, 0, 0}
    assert :stale = Raw.callback_fixture_reply_code(token, true, 9)
  end

  test "callback fixture detects a stale callback owner" do
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        callback = fn _handle, _range -> {:ok, {1, 2}} end
        send(parent, {:registration, Raw.callback_fixture_register(callback, nil, 100)})
        Process.sleep(:infinity)
      end)

    assert_receive {:registration, registration}
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}

    assert :ok = Raw.callback_fixture_invoke_on_worker(registration, 1)
    assert_receive {:callback_fixture_error, :FailedToSendCallback}
  end

  @tag :tmp_dir
  test "callback fixture survives hot upgrade and worker destruction", %{
    tmp_dir: tmp_dir
  } do
    parent = self()

    destructor = fn ->
      send(parent, :destructor_called)
      {:ok, :destroyed}
    end

    registration = Raw.callback_fixture_register(fn _, _ -> {:ok, {0, 0}} end, destructor, 1_000)

    upgrade_nif = Path.join(tmp_dir, "libKindaExampleNIFUpgrade")
    source_nif = "#{:code.priv_dir(:kinda_example)}/lib/libKindaExampleNIF.so"
    File.cp!(source_nif, "#{upgrade_nif}.so")

    {Raw, original_beam, original_path} = :code.get_object_code(Raw)

    on_exit(fn ->
      assert {:module, Raw} = :code.load_binary(Raw, original_path, original_beam)
      :code.purge(Raw)
    end)

    assert {:module, Raw, _upgrade_beam, _on_load_result} =
             hot_upgrade_raw_module(upgrade_nif)

    :code.purge(Raw)

    assert :ok = Raw.callback_fixture_destroy_on_worker(registration)
    assert_receive {:destruct, token, ^destructor, _id}

    assert {:ok, :destroyed} =
             Kinda.CallbackRuntime.invoke_reply(token, destructor, fn token, outcome ->
               Raw.callback_fixture_reply_code(token, match?({:ok, _}, outcome), 0)
             end)

    assert_receive :destructor_called
    assert_receive {:callback_fixture_destroyed, :replied, true, 0, 0}

    assert :ok = Raw.callback_fixture_invoke_on_worker(registration, 1)
    assert_receive {:callback_fixture_error, :registration_closed}
  end

  defp reply_projection(token, {:ok, {code, projection}}),
    do: Raw.callback_fixture_reply_projection(token, true, code, projection)

  defp reply_projection(token, _outcome),
    do: Raw.callback_fixture_reply_projection(token, false, 0, 0)

  defp lifecycle_counts_reached?(counts, baseline, increments) do
    counts
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(baseline))
    |> Enum.zip(Tuple.to_list(increments))
    |> Enum.all?(fn {{count, initial}, increment} -> count >= initial + increment end)
  end

  defp assert_eventually(assertion, attempts \\ 100)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      :ok
    else
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(assertion, 0), do: assert(assertion.())

  defp hot_upgrade_raw_module(nif_file) do
    stubs =
      for {name, arity} <- Raw.__info__(:functions), name != :load_nif do
        args = Macro.generate_arguments(arity, __MODULE__)

        quote do
          def unquote(name)(unquote_splicing(args)),
            do: :erlang.nif_error({:nif_not_loaded, unquote(name)})
        end
      end

    body =
      quote do
        @on_load :load_nif

        def load_nif do
          :erlang.load_nif(unquote(String.to_charlist(nif_file)), 0)
        end

        unquote_splicing(stubs)
      end

    compiler_options = Code.compiler_options()
    Code.compiler_options(ignore_module_conflict: true)

    try do
      Module.create(Raw, body, Macro.Env.location(__ENV__))
    after
      Code.compiler_options(compiler_options)
    end
  end
end
