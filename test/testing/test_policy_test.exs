defmodule Kinda.Testing.TestPolicyTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "accepts AST-shaped async and ExUnit tmp-dir conventions", %{tmp_dir: tmp_dir} do
    write_source!(tmp_dir, "test/valid_test.exs", """
    defmodule ValidTest do
      use ExUnit.Case,
        async: true

      @tag :tmp_dir
      test "atom tag", %{tmp_dir: tmp_dir}, do: assert(is_binary(tmp_dir))

      @tag tmp_dir: true
      test "keyword tag", %{tmp_dir: tmp_dir}, do: assert(is_binary(tmp_dir))

      test "text is inert" do
        assert "System.tmp_dir!()" =~ "tmp_dir"
        # System.tmp_dir()
      end
    end
    """)

    assert {output, 0} = run_policy(tmp_dir)
    assert output =~ "test policy OK (1 files scanned)"
  end

  @tag :tmp_dir
  test "reports module-level async and direct tmp-dir violations", %{tmp_dir: tmp_dir} do
    write_source!(tmp_dir, "test/multiple_test.exs", """
    defmodule AsyncTest do
      use ExUnit.Case, async: true
    end

    defmodule SynchronousTest do
      use ExUnit.Case
    end
    """)

    write_source!(tmp_dir, "test/support/fixture.ex", """
    defmodule Fixture do
      def directory, do: System.tmp_dir!()
      def optional_directory, do: System.tmp_dir()
    end
    """)

    assert {output, 1} = run_policy(tmp_dir)
    assert output =~ "missing_async (SynchronousTest)"
    refute output =~ "missing_async (AsyncTest)"
    assert output =~ "tmp_dir_called"
    assert output |> String.split("tmp_dir_called") |> length() == 3
    assert output =~ "test/support/fixture.ex"
  end

  @tag :tmp_dir
  test "does not inspect quoted code or require async in support modules", %{tmp_dir: tmp_dir} do
    write_source!(tmp_dir, "test/support/case.ex", """
    defmodule SupportCase do
      use ExUnit.Case

      def quoted do
        quote do
          System.tmp_dir!()
        end
      end
    end
    """)

    assert {_output, 0} = run_policy(tmp_dir)
  end

  defp run_policy(root) do
    System.cmd(
      System.find_executable("elixir"),
      ["scripts/check_test_policy.exs", root],
      cd: Path.expand("../..", __DIR__),
      stderr_to_stdout: true
    )
  end

  defp write_source!(root, relative_path, contents) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end
end
