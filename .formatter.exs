# Used by "mix format"
[
  inputs:
    ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"] ++
      ["kinda_example/{mix,.formatter}.exs", "kinda_example/{config,lib,test}/**/*.{ex,exs}"] ++
      [
        "kinda_sqlite_example/{mix,.formatter}.exs",
        "kinda_sqlite_example/{lib,test}/**/*.{ex,exs}"
      ]
]
