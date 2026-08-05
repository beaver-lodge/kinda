defmodule Kinda.CallbackRuntimeTest do
  use ExUnit.Case, async: true

  alias Kinda.CallbackRuntime

  test "replies success for an ok callback" do
    owner = self()
    reply = fn token, success -> send(owner, {:reply, token, success}) end

    assert CallbackRuntime.invoke(:token, fn -> {:ok, :state} end, reply) == {:ok, :state}
    assert_receive {:reply, :token, true}
  end

  test "replies failure while preserving an expected callback error" do
    owner = self()
    reply = fn token, success -> send(owner, {:reply, token, success}) end

    assert CallbackRuntime.invoke(:token, fn -> {:error, :state} end, reply) ==
             {:error, :state}

    assert_receive {:reply, :token, false}
  end

  test "replies failure and returns exception context" do
    owner = self()
    reply = fn token, success -> send(owner, {:reply, token, success}) end

    assert {:exception, :error, %RuntimeError{message: "boom"}, stacktrace} =
             CallbackRuntime.invoke(:token, fn -> raise "boom" end, reply)

    assert is_list(stacktrace)
    assert_receive {:reply, :token, false}
  end

  test "treats an invalid callback return as an exception" do
    owner = self()
    reply = fn token, success -> send(owner, {:reply, token, success}) end

    assert {:exception, :error, %ArgumentError{}, _stacktrace} =
             CallbackRuntime.invoke(:token, fn -> :invalid end, reply)

    assert_receive {:reply, :token, false}
  end

  test "runs the outcome observer before replying" do
    owner = self()
    observer = fn outcome -> send(owner, {:observed, outcome}) end

    reply = fn token, success ->
      assert_received {:observed, {:error, :state}}
      send(owner, {:reply, token, success})
    end

    assert CallbackRuntime.invoke(:token, fn -> {:error, :state} end, reply, observer) ==
             {:error, :state}

    assert_receive {:reply, :token, false}
  end
end
