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

  test "lets a consumer encode a projected result from the normalized outcome" do
    owner = self()

    reply = fn token, outcome ->
      send(owner, {:reply, token, outcome})
    end

    assert CallbackRuntime.invoke_reply(:token, fn -> {:ok, {:success, 42}} end, reply) ==
             {:ok, {:success, 42}}

    assert_receive {:reply, :token, {:ok, {:success, 42}}}
  end
end
