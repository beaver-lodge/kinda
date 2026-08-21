defmodule Kinda.Sandbox.LocalProcessCommandTest do
  use ExUnit.Case, async: true

  alias Kinda.Sandbox
  alias Kinda.Sandbox.Backend.LocalProcess
  alias Kinda.Sandbox.Backend.LocalProcess.Spec, as: BackendSpec
  alias Kinda.Sandbox.Command
  alias Kinda.Sandbox.Command.Spec

  @tag :tmp_dir
  test "executes an exact executable and argv without shell interpretation", %{tmp_dir: parent} do
    {:ok, sandbox} = Sandbox.create(LocalProcess, backend_spec(parent))
    literal = "$(echo expanded); *.ex"

    assert {:ok, result} =
             Command.run(sandbox, %Spec{
               executable: erl(),
               args: [
                 "-noshell",
                 "-eval",
                 "[Arg] = init:get_plain_arguments(), io:put_chars(Arg), halt().",
                 "-extra",
                 literal
               ],
               inherit_env: runtime_env(),
               env: %{"LANG" => "C.UTF-8"}
             })

    assert result.termination == {:exit, 0}
    assert result.stdout == literal
    assert result.stderr == ""
    assert result.metadata.streams == expected_streams()
    refute result.metadata.process_tree_termination?
    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "uses the owned cwd and explicit environment without ambient values", %{tmp_dir: parent} do
    {:ok, sandbox} =
      Sandbox.create(LocalProcess, %BackendSpec{
        parent_directory: parent,
        env: %{"SANDBOX_BASE" => "base"}
      })

    code = ~S'''
    Value = fun(Name) -> case os:getenv(Name) of false -> ""; V -> V end end,
    {ok, Cwd} = file:get_cwd(),
    io:format("~s|~s|~s|~s", [filename:basename(Cwd), Value("SANDBOX_BASE"), Value("COMMAND_VALUE"), Value("HOME")]),
    halt().
    '''

    assert {:ok, result} =
             Command.run(sandbox, %Spec{
               executable: erl(),
               args: ["-noshell", "-eval", code],
               env: %{"COMMAND_VALUE" => "command", "LANG" => "C.UTF-8"},
               inherit_env: runtime_env()
             })

    [directory, "base", "command", ""] = String.split(result.stdout, "|")
    assert String.starts_with?(directory, "kinda-process-")
    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "writes binary stdin and reports spawn failures", %{tmp_dir: parent} do
    {:ok, sandbox} = Sandbox.create(LocalProcess, backend_spec(parent))

    assert {:ok, result} =
             Command.run(sandbox, %Spec{
               executable: erl(),
               args: [
                 "-noshell",
                 "-eval",
                 ~S|io:setopts(standard_io, [binary, {encoding, latin1}]), Data = io:get_chars(standard_io, "", 4), io:put_chars(Data), halt().|
               ],
               stdin: <<0, 1, 2, 255>>,
               inherit_env: runtime_env(),
               env: %{"LANG" => "C.UTF-8"}
             })

    assert result.stdout == <<0, 1, 2, 255>>
    assert result.termination == {:exit, 0}

    assert {:ok, failed} =
             Command.run(sandbox, %Spec{executable: Path.join(parent, "does-not-exist")})

    assert failed.termination == :spawn_failure
    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "captures stderr in an explicitly reported merged stream", %{tmp_dir: parent} do
    {:ok, sandbox} = Sandbox.create(LocalProcess, backend_spec(parent))

    assert {:ok, result} =
             Command.run(sandbox, %Spec{
               executable: erl(),
               args: [
                 "-noshell",
                 "-eval",
                 ~S|io:put_chars(standard_io, "out"), io:put_chars(standard_error, "err"), halt().|
               ],
               inherit_env: runtime_env(),
               env: %{"LANG" => "C.UTF-8"}
             })

    if windows?() do
      assert result.stdout =~ "out"
      assert result.stdout =~ "err"
      assert result.stderr == ""
    else
      assert result.stdout == "out"
      assert result.stderr == "err"
    end

    assert result.metadata.streams == expected_streams()
    assert :ok = Sandbox.close(sandbox)
  end

  defp backend_spec(parent) do
    %BackendSpec{parent_directory: parent}
  end

  defp erl, do: System.find_executable("erl") || raise("erl executable unavailable")

  defp runtime_env do
    ["PATH", "SYSTEMROOT", "SystemRoot", "COMSPEC", "ComSpec", "PATHEXT", "TEMP", "TMP"]
  end

  defp expected_streams, do: if(windows?(), do: :merged, else: :separate)
  defp windows?, do: match?({:win32, _name}, :os.type())
end
