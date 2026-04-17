defmodule Kinda.SystemCommandRunner do
  @moduledoc false

  @spec cmd(binary(), [binary()], keyword()) :: {binary(), non_neg_integer()}
  def cmd(command, args, opts) do
    System.cmd(command, args, opts)
  end
end
