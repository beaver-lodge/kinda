# Used by "mix format"
[
  inputs:
    ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"] ++
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
      ]
]
