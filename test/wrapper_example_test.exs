defmodule Kinda.WrapperExampleTest do
  use ExUnit.Case, async: true

  test "wrapper reporting example is runnable" do
    root = Path.expand("..", __DIR__)

    {output, status} =
      System.cmd("elixir", ["examples/wrapper_reporting.exs"],
        cd: root,
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "Callback Bridge Report"
    assert output =~ "callback_bridge_required"
    assert output =~ "\"version\":1"
  end
end
