defmodule Kinda.ErrorTest do
  use ExUnit.Case, async: true

  alias Kinda.CodeGen.{DeclarationManifest, DeclarationSurfaces, KindDecl}

  defmodule MissingManifest do
  end

  test "command errors retain process context without text parsing" do
    runner = fn _command, _args, _opts -> {"bad input\n", 23} end

    error =
      assert_raise Kinda.CommandError, fn ->
        Kinda.SystemCommandRunner.run!(
          runner,
          "tool",
          ["generate", "input file"],
          [cd: "/tmp/project"],
          stage: :generation
        )
      end

    assert error.stage == :generation
    assert error.command == "tool"
    assert error.args == ["generate", "input file"]
    assert error.cwd == "/tmp/project"
    assert error.status == 23
    assert error.output == "bad input\n"
    assert Exception.message(error) =~ "command: tool generate input file"
  end

  test "command launch failures retain the operating-system reason" do
    error =
      assert_raise Kinda.CommandError, fn ->
        Kinda.SystemCommandRunner.run!(
          Kinda.SystemCommandRunner,
          "kinda-command-that-does-not-exist",
          [],
          [],
          stage: :generation
        )
      end

    assert error.stage == :generation
    assert error.command == "kinda-command-that-does-not-exist"
    assert error.status == nil
    assert error.reason == :enoent
  end

  test "manifest source errors expose a stable generation reason" do
    error =
      assert_raise Kinda.GenerationError, fn ->
        DeclarationManifest.load!("declarations.yaml")
      end

    assert error.stage == :declaration_loading
    assert error.reason == :unsupported_manifest_extension
    assert error.expected == [".ex", ".json"]
    assert error.actual == ".yaml"
    assert error.source == Path.expand("declarations.yaml")
  end

  test "generator contract errors identify the missing callback" do
    error =
      assert_raise Kinda.GenerationError, fn ->
        DeclarationSurfaces.load_source(MissingManifest)
      end

    assert error.reason == :missing_declaration_manifest
    assert error.source == MissingManifest
    assert error.expected == {:declaration_manifest, 0}
  end

  test "unsupported kinds retain the generator and type" do
    type = {:vector, 4, :i32}

    error =
      assert_raise Kinda.GenerationError, fn ->
        KindDecl.default(__MODULE__, type)
      end

    assert error.stage == :kind_resolution
    assert error.reason == :unsupported_type
    assert error.source == __MODULE__
    assert error.actual == type
  end

  test "NIF load errors retain the path and native reason" do
    error = %Kinda.NIFLoadError{path: ~c"/tmp/libExample", reason: {:load_failed, "bad ABI"}}

    assert Exception.message(error) =~ "NIF load failed"
    assert Exception.message(error) =~ "/tmp/libExample"
    assert Exception.message(error) =~ "bad ABI"
  end
end
