# Used by "mix format"
[
  inputs:
    ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"] ++
      ["kinda_example/{mix,.formatter}.exs", "kinda_example/{config,lib,test}/**/*.{ex,exs}"] ++
      [
        "packages/kinda_sqlite/{mix,.formatter}.exs",
        "packages/kinda_sqlite/{lib,test}/**/*.{ex,exs}"
      ]
]
