defmodule Flux.AI.Supervisor do
  @moduledoc """
  Starts the active AI provider process (if it needs one) under a
  one_for_one supervisor. The Basic Community provider is stateless and
  contributes no children; EE providers such as `Flux.AI.Detector`
  expose `child_spec/1` and run here.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    provider = Flux.AI.Registry.active()

    children =
      if function_exported?(provider, :child_spec, 1) do
        [provider]
      else
        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
