# Used by "mix format"
[
  subdirectories: ["lib"],
  inputs:
    ["{mix,.formatter}.exs", "{config,test}/**/*.{ex,exs}", "scripts/*.exs"] ++
      [
        "packages/kinda_example/{mix,.formatter}.exs",
        "packages/kinda_example/{config,lib,test}/**/*.{ex,exs}"
      ] ++
      [
        "packages/kinda_sqlite/{mix,.formatter}.exs",
        "packages/kinda_sqlite/{lib,test}/**/*.{ex,exs}"
      ] ++
      [
        "packages/kinda_python/{mix,.formatter}.exs",
        "packages/kinda_python/{lib,test,scripts}/**/*.{ex,exs}"
      ] ++
      [
        "packages/kinda_mruby/{mix,.formatter}.exs",
        "packages/kinda_mruby/{lib,test,scripts}/**/*.{ex,exs}"
      ]
]
