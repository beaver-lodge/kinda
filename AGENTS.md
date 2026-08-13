# Kinda Agent Guidelines

## Elixir Tests

- Every module that directly uses `ExUnit.Case` must enable parallel execution
  with `use ExUnit.Case, async: true`.
- Test code must use ExUnit's built-in `@tag :tmp_dir` (or
  `@tag tmp_dir: true`) and receive `%{tmp_dir: tmp_dir}` from the test context.
  Do not allocate test directories with `System.tmp_dir/0` or
  `System.tmp_dir!/0`; pass the ExUnit directory into test-support helpers.
- Avoid test designs that mutate process-global or VM-global state such as the
  current working directory or OS environment.
- Run `elixir scripts/check_test_policy.exs test packages` to verify these
  repository-wide rules. Package workflows may pass their own `test` directory.
