defmodule Kinda.Capsule.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Kinda.Capsule.Registry},
      {Registry, keys: :unique, name: Kinda.Capsule.ExecutionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Kinda.Capsule.ServerSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Kinda.Capsule.ExecutionSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Kinda.Capsule.Supervisor)
  end
end
