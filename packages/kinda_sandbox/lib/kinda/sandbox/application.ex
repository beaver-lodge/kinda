defmodule Kinda.Sandbox.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Kinda.Sandbox.Registry},
      {Registry, keys: :unique, name: Kinda.Sandbox.ExecutionRegistry},
      {Task.Supervisor, name: Kinda.Sandbox.CommandTaskSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Kinda.Sandbox.HandleSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Kinda.Sandbox.ExecutionSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Kinda.Sandbox.Supervisor)
  end
end
