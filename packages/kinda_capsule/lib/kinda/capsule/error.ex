defmodule Kinda.Capsule.Error do
  @moduledoc "Normalized failure at a Capsule orchestration boundary."

  @phases [:create, :reset, :execute, :observe, :grade, :trace, :close]

  defexception [:phase, :reason, :cause, :details, message: "capsule operation failed"]

  @type phase :: :create | :reset | :execute | :observe | :grade | :trace | :close
  @type t :: %__MODULE__{
          phase: phase(),
          reason: atom(),
          cause: term(),
          details: term(),
          message: binary()
        }

  @spec phases() :: [phase()]
  def phases, do: @phases
end
