defmodule Kinda.ZigAST do
  @moduledoc false
  @keywords ~w{
  align
  allowzero
  and
  anyframe
  anytype
  asm
  async
  await
  break
  callconv
  catch
  comptime
  const
  continue
  defer
  else
  enum
  errdefer
  error
  export
  extern
  fn
  for
  if
  inline
  noalias
  nosuspend
  noinline
  opaque
  or
  orelse
  packed
  pub
  resume
  return
  linksection
  struct
  suspend
  switch
  test
  threadlocal
  try
  union
  unreachable
  usingnamespace
  var
  volatile
  while
} |> Enum.map(&String.to_atom/1)

  def is_keyword?(txt) when is_atom(txt) do
    txt |> Atom.to_string() |> is_keyword?
  end

  def is_keyword?(txt) when is_binary(txt) do
    txt in @keywords or txt in ~w{type}
  end

  def extract_item_type(
        {:cptr,
         %Zig.Parser.PointerOptions{
           align: nil,
           const: true,
           volatile: false,
           allowzero: false
         }, [type: type]}
      ) do
    {:ok, type}
  end

  def extract_item_type(
        {:cptr,
         %Zig.Parser.PointerOptions{
           align: nil,
           const: false,
           volatile: false,
           allowzero: false
         }, [type: type]}
      ) do
    {:ok, type}
  end

  def extract_item_type(_type) do
    {:error, "not a pointer or array type"}
  end

  def is_array?(
        {:cptr,
         %Zig.Parser.PointerOptions{
           align: nil,
           const: true,
           volatile: false,
           allowzero: false
         }, [type: _type]}
      ),
      do: true

  def is_array?(_),
    do: false

  def is_ptr?(
        {:cptr,
         %Zig.Parser.PointerOptions{
           align: nil,
           const: false,
           volatile: false,
           allowzero: false
         }, [type: _type]}
      ),
      do: true

  def is_ptr?(_),
    do: false
end
