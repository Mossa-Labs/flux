defmodule Flux.Queue.Supervisor do
  @moduledoc """
  Resolves the active queue adapter from `Flux.Queue.Registry` at
  boot-time and starts it under a one_for_one supervisor. Sits in
  `Flux.Application`'s child list after `Flux.Registrations` so the
  registry is populated before `init/1` runs.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    {:ok, adapter} = Flux.Queue.Registry.active()
    children = [{adapter, name: adapter}]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
