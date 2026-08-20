defmodule Kinda.Sandbox.ShellTest do
  use ExUnit.Case, async: true

  alias Kinda.Sandbox
  alias Kinda.Sandbox.Backend.LocalNative
  alias Kinda.Sandbox.Backend.LocalNative.Spec, as: BackendSpec
  alias Kinda.Sandbox.Command.Result
  alias Kinda.Sandbox.{Error, Shell}

  @tag :tmp_dir
  test "POSIX profile is explicit and does not inject error policy", %{tmp_dir: parent} do
    {:ok, sandbox} = Sandbox.create(LocalNative, backend_spec(parent))

    if System.find_executable("sh") do
      assert {:ok, %Result{} = result} =
               Shell.run(sandbox, "false\nprintf continued",
                 env: base_env(),
                 inherit_env: ["PATH"]
               )

      assert result.termination == {:exit, 0}
      assert result.stdout == "continued"
      assert result.metadata.shell.profile == :posix_sh
      assert Path.basename(result.metadata.shell.executable) in ["sh", "sh.exe", "dash"]
    else
      assert {:error, %Error{reason: :unsupported_capability, operation: :shell}} =
               Shell.run(sandbox, "printf ignored")
    end

    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "exact-path profile preserves caller arguments and script as one argv", %{tmp_dir: parent} do
    {:ok, sandbox} = Sandbox.create(LocalNative, backend_spec(parent))

    if sh = System.find_executable("sh") do
      script = ~S|printf '%s' 'literal;$(shell-text)'|

      assert {:ok, result} =
               Shell.run(sandbox, script,
                 interpreter: {:path, sh, ["-u"]},
                 env: base_env(),
                 inherit_env: ["PATH"]
               )

      assert result.stdout == "literal;$(shell-text)"
      assert result.metadata.shell.profile == {:path, sh, ["-u"]}
    end

    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "Bash and Zsh profiles are exact, conditional, and skip user startup files", %{
    tmp_dir: parent
  } do
    {:ok, sandbox} = Sandbox.create(LocalNative, backend_spec(parent))

    for {profile, startup_file} <- [bash: ".bashrc", zsh: ".zshrc"],
        executable = System.find_executable(Atom.to_string(profile)),
        executable do
      home = Path.join(parent, Atom.to_string(profile))
      File.mkdir_p!(home)
      File.write!(Path.join(home, startup_file), "printf startup-loaded")

      assert {:ok, result} =
               Shell.run(sandbox, "printf clean",
                 interpreter: profile,
                 env: Map.merge(base_env(), %{"HOME" => home, "ZDOTDIR" => home}),
                 inherit_env: ["PATH"]
               )

      assert result.stdout == "clean"
      assert result.metadata.shell.profile == profile
      assert result.metadata.shell.executable == executable
    end

    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "does not fall back when an interpreter or option is invalid", %{tmp_dir: parent} do
    {:ok, sandbox} = Sandbox.create(LocalNative, backend_spec(parent))

    assert {:error, %Error{reason: :invalid_spec, operation: :shell}} =
             Shell.run(sandbox, "echo ignored", interpreter: :fish)

    assert {:error, %Error{reason: :invalid_spec, operation: :shell}} =
             Shell.run(sandbox, "echo ignored", unknown: true)

    assert :ok = Sandbox.close(sandbox)
  end

  defp backend_spec(parent), do: %BackendSpec{base_module: __MODULE__, parent_directory: parent}
  defp base_env, do: %{"LANG" => "C.UTF-8"}
end
