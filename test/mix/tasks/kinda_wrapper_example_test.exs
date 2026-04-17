defmodule Mix.Tasks.Kinda.Wrapper.ExampleTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "prints the wrapper reporting example" do
    Mix.Task.reenable("kinda.wrapper.example")

    output =
      capture_io(fn ->
        Mix.Task.run("kinda.wrapper.example")
      end)

    assert output =~ "== Elixir Manifest =="
    assert output =~ "== Callback Bridge Report =="
    assert output =~ "== Callback Bridge Manifest =="
    assert output =~ "callback_bridge_required"
    assert output =~ "\"version\":1"
  end

  test "supports json-only output" do
    Mix.Task.reenable("kinda.wrapper.example")

    output =
      capture_io(fn ->
        Mix.Task.run("kinda.wrapper.example", ["--json"])
      end)

    assert output =~ "\"version\":1"
    assert output =~ "\"callback_bridge_required\""
    refute output =~ "== Elixir Manifest =="
    refute output =~ "== Callback Bridge Report =="
  end

  test "supports report-only output" do
    Mix.Task.reenable("kinda.wrapper.example")

    output =
      capture_io(fn ->
        Mix.Task.run("kinda.wrapper.example", ["--report-only"])
      end)

    assert output =~ "== Callback Bridge Report =="
    assert output =~ "callback_bridge_required"
    refute output =~ "== Elixir Manifest =="
    refute output =~ "== Callback Bridge Manifest =="
  end
end
