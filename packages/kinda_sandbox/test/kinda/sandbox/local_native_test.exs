defmodule Kinda.Sandbox.LocalNativeTest do
  use ExUnit.Case, async: true

  alias Kinda.Sandbox
  alias Kinda.Sandbox.Backend.LocalNative
  alias Kinda.Sandbox.Backend.LocalNative.Spec
  alias Kinda.Sandbox.Capability.NativeBuild.Context
  alias Kinda.Sandbox.{Error, NativeBuild}

  def write_artifact(test_pid, contents, %Context{} = context) do
    send(test_pid, {:build_context, context})
    path = Path.join(context.directory, "fixture.so")
    File.write!(path, to_string(contents))
    path
  end

  def write_partial_then_fail(test_pid, %Context{} = context) do
    partial = Path.join(context.directory, "partial.o")
    File.write!(partial, "partial")
    send(test_pid, {:partial, partial})
    {:error, Error.exception(reason: :backend_failure, message: "compiler failed")}
  end

  def write_outside(path, %Context{} = context) do
    File.write!(Path.join(context.directory, "partial.o"), "partial")
    File.write!(path, "outside")
    path
  end

  def return_path(path, _context), do: path

  def block_build(test_pid, gate, %Context{} = context) do
    send(test_pid, {:builder_entered, gate})

    receive do
      {:continue, ^gate} -> write_artifact(test_pid, gate, context)
    end
  end

  test "allocates unique module, entry name, and owned child directory" do
    parent = temporary_parent!()
    on_exit(fn -> File.rm_rf!(parent) end)
    spec = %Spec{base_module: __MODULE__, parent_directory: parent, env: %{"CC" => "zig cc"}}

    assert {:ok, first} = Sandbox.create(LocalNative, spec)
    assert {:ok, second} = Sandbox.create(LocalNative, spec)

    assert {:ok, first_artifact} =
             NativeBuild.build(first, {__MODULE__, :write_artifact, [self(), "first"]})

    assert_receive {:build_context, first_context}
    assert first_context.entry_name == Atom.to_string(first_context.module)
    assert first_context.env == %{"CC" => "zig cc"}
    assert Path.dirname(first_context.directory) == Path.expand(parent)

    assert {:ok, _second_artifact} =
             NativeBuild.build(second, {__MODULE__, :write_artifact, [self(), "second"]})

    assert_receive {:build_context, second_context}
    refute first_context.module == second_context.module
    refute first_context.entry_name == second_context.entry_name
    refute first_context.directory == second_context.directory
    assert File.read!(first_artifact) == "first"

    assert :ok = Sandbox.close(first)
    refute File.exists?(first_context.directory)
    assert File.dir?(parent)
    assert :ok = Sandbox.close(second)
    assert File.dir?(parent)
  end

  test "failed builds clean partial output and remain retryable" do
    parent = temporary_parent!()
    on_exit(fn -> File.rm_rf!(parent) end)

    {:ok, handle} =
      Sandbox.create(LocalNative, %Spec{base_module: __MODULE__, parent_directory: parent})

    assert {:error, %Error{reason: :backend_failure}} =
             NativeBuild.build(handle, {__MODULE__, :write_partial_then_fail, [self()]})

    assert_receive {:partial, partial}
    refute File.exists?(partial)
    assert File.dir?(Path.dirname(partial))

    assert {:ok, artifact} =
             NativeBuild.build(handle, {__MODULE__, :write_artifact, [self(), "retry"]})

    assert File.read!(artifact) == "retry"
    assert :ok = Sandbox.close(handle)
  end

  test "rejects artifacts outside the owned child and cleans only the child" do
    parent = temporary_parent!()
    on_exit(fn -> File.rm_rf!(parent) end)
    outside = Path.join(parent, "outside.so")

    {:ok, handle} =
      Sandbox.create(LocalNative, %Spec{base_module: __MODULE__, parent_directory: parent})

    assert {:error, %Error{reason: :backend_failure}} =
             NativeBuild.build(handle, {__MODULE__, :write_outside, [outside]})

    assert File.regular?(outside)

    assert {:ok, artifact} =
             NativeBuild.build(handle, {__MODULE__, :write_artifact, [self(), "safe"]})

    refute Path.dirname(artifact) == Path.dirname(outside)
    assert :ok = Sandbox.close(handle)
    assert File.regular?(outside)
  end

  test "serializes builds for one handle" do
    parent = temporary_parent!()
    on_exit(fn -> File.rm_rf!(parent) end)

    {:ok, handle} =
      Sandbox.create(LocalNative, %Spec{base_module: __MODULE__, parent_directory: parent})

    test_pid = self()

    first =
      Task.async(fn ->
        NativeBuild.build(handle, {__MODULE__, :block_build, [test_pid, :first]})
      end)

    assert_receive {:builder_entered, :first}

    second =
      Task.async(fn ->
        NativeBuild.build(handle, {__MODULE__, :block_build, [test_pid, :second]})
      end)

    refute_receive {:builder_entered, :second}

    send(server_pid(handle), {:continue, :first})
    assert {:ok, _artifact} = Task.await(first)
    assert_receive {:builder_entered, :second}
    send(server_pid(handle), {:continue, :second})
    assert {:ok, _artifact} = Task.await(second)
    assert :ok = Sandbox.close(handle)
  end

  test "reports unsupported capabilities and validates specs" do
    assert {:error, %Error{reason: :invalid_spec}} = Sandbox.create(LocalNative, :invalid)

    assert {:error, %Error{reason: :invalid_spec}} =
             Sandbox.create(LocalNative, %Spec{base_module: "not a module"})

    assert {:ok, handle} = Sandbox.create(Kinda.Sandbox.FakeBackend, {:notify, self()})

    assert {:error, %Error{reason: :unsupported_capability}} =
             NativeBuild.build(handle, {__MODULE__, :write_artifact, [self(), "unused"]})

    assert :ok = Sandbox.close(handle)
  end

  test "rejects missing and non-regular artifacts" do
    parent = temporary_parent!()
    on_exit(fn -> File.rm_rf!(parent) end)

    {:ok, handle} =
      Sandbox.create(LocalNative, %Spec{base_module: __MODULE__, parent_directory: parent})

    assert {:error, %Error{reason: :backend_failure}} =
             NativeBuild.build(handle, {__MODULE__, :return_path, ["missing.so"]})

    assert {:error, %Error{reason: :backend_failure}} =
             NativeBuild.build(handle, {__MODULE__, :return_path, ["."]})

    assert :ok = Sandbox.close(handle)
  end

  test "failed creation does not remove or mutate the supplied parent path" do
    path =
      Path.join(
        System.tmp_dir!(),
        "kinda-parent-file-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.write!(path, "owned by caller")
    on_exit(fn -> File.rm!(path) end)

    assert {:error, %Error{reason: :backend_failure}} =
             Sandbox.create(LocalNative, %Spec{base_module: __MODULE__, parent_directory: path})

    assert File.read!(path) == "owned by caller"
  end

  defp temporary_parent! do
    path =
      Path.join(
        System.tmp_dir!(),
        "kinda-sandbox-test-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end

  defp server_pid(%Kinda.Sandbox.Handle{ref: ref}) do
    [{pid, _value}] = Registry.lookup(Kinda.Sandbox.Registry, ref)
    pid
  end
end
