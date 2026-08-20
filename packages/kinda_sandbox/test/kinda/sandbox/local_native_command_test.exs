defmodule Kinda.Sandbox.LocalNativeCommandTest do
  use ExUnit.Case, async: true

  alias Kinda.Sandbox
  alias Kinda.Sandbox.Backend.LocalNative
  alias Kinda.Sandbox.Backend.LocalNative.Spec, as: BackendSpec
  alias Kinda.Sandbox.Command
  alias Kinda.Sandbox.Command.Spec

  @tag :tmp_dir
  test "executes an exact executable and argv without shell interpretation", %{tmp_dir: parent} do
    {:ok, sandbox} = Sandbox.create(LocalNative, backend_spec(parent))
    literal = "$(echo expanded); *.ex"

    assert {:ok, result} =
             Command.run(sandbox, %Spec{
               executable: elixir(),
               args: ["-e", "IO.write(hd(System.argv()))", "--", literal],
               inherit_env: ["PATH"],
               env: %{"LANG" => "C.UTF-8"}
             })

    assert result.termination == {:exit, 0}
    assert result.stdout == literal
    assert result.stderr == ""
    assert result.metadata.streams == :merged
    refute result.metadata.process_tree_termination?
    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "uses the owned cwd and explicit environment without ambient values", %{tmp_dir: parent} do
    {:ok, sandbox} =
      Sandbox.create(LocalNative, %BackendSpec{
        base_module: __MODULE__,
        parent_directory: parent,
        env: %{"SANDBOX_BASE" => "base"}
      })

    code =
      ~S"""
      IO.write(Enum.join([Path.basename(File.cwd!()), System.get_env("SANDBOX_BASE"), System.get_env("COMMAND_VALUE"), System.get_env("HOME")], "|"))
      """

    assert {:ok, result} =
             Command.run(sandbox, %Spec{
               executable: elixir(),
               args: ["-e", code],
               env: %{"COMMAND_VALUE" => "command", "LANG" => "C.UTF-8"},
               inherit_env: ["PATH"]
             })

    [directory, "base", "command", ""] = String.split(result.stdout, "|")
    assert String.starts_with?(directory, "kinda-sandbox-")
    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "writes binary stdin and reports spawn failures", %{tmp_dir: parent} do
    {:ok, sandbox} = Sandbox.create(LocalNative, backend_spec(parent))

    assert {:ok, result} =
             Command.run(sandbox, %Spec{
               executable: elixir(),
               args: ["-e", "IO.binwrite(IO.binread(:stdio, :eof))"],
               stdin: <<0, 1, 2, 255>>,
               inherit_env: ["PATH"],
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
    {:ok, sandbox} = Sandbox.create(LocalNative, backend_spec(parent))

    assert {:ok, result} =
             Command.run(sandbox, %Spec{
               executable: elixir(),
               args: ["-e", ~S|IO.write(:stdio, "out"); IO.write(:stderr, "err")|],
               inherit_env: ["PATH"],
               env: %{"LANG" => "C.UTF-8"}
             })

    assert result.stdout =~ "out"
    assert result.stdout =~ "err"
    assert result.stderr == ""
    assert result.metadata.streams == :merged
    assert :ok = Sandbox.close(sandbox)
  end

  defp backend_spec(parent) do
    %BackendSpec{base_module: __MODULE__, parent_directory: parent}
  end

  defp elixir, do: System.find_executable("elixir") || raise("elixir executable unavailable")
end
