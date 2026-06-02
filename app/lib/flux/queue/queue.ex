defmodule Flux.Queue do
  @moduledoc """
  Facade for queue adapters. The adapter contract lives in `Flux.Queue.Adapter`.

  Adapters are registered at boot against a string type identifier in
  `Flux.Queue.Registry`; the configured `:active` queue type (set via
  `config :flux, Flux.Queue, type: "memory"`) is resolved on each call.

  ## Usage

      alias Flux.Queue
      alias Flux.Queue.Message

      message = Message.new(%{event: "user.created", data: %{id: 1}}, source: "webhook")
      :ok = Queue.publish("webhooks.github", message)

  """

  alias Flux.Queue.Message

  @type queue_name :: Flux.Queue.Adapter.queue_name()
  @type publish_opts :: Flux.Queue.Adapter.publish_opts()
  @type error :: Flux.Queue.Adapter.error()

  @doc """
  Returns the currently active queue adapter module.

  Resolves via `Flux.Queue.Registry.active/0`, which is seeded at boot from
  the `:type` key under `config :flux, Flux.Queue`. Raises if no active
  adapter has been set.
  """
  @spec adapter() :: module()
  def adapter do
    case Flux.Queue.Registry.active() do
      {:ok, module} ->
        module

      {:error, :no_active_adapter} ->
        raise "No active queue adapter. Set config :flux, Flux.Queue, type: \"memory\" (or another registered type)."
    end
  end

  @doc """
  Publishes a message using the configured adapter.

  ## Examples

      message = Flux.Queue.Message.new(%{event: "test"}, source: "api")
      :ok = Flux.Queue.publish("events", message)

  """
  @spec publish(queue_name(), Message.t(), publish_opts()) :: :ok | error()
  def publish(queue, %Message{} = message, opts \\ []) do
    adapter().publish(queue, message, opts)
  end

  @doc """
  Acknowledges a message using the configured adapter.
  """
  @spec ack(Message.t()) :: :ok | error()
  def ack(%Message{} = message) do
    adapter().ack(message)
  end

  @doc """
  Rejects a message using the configured adapter.

  ## Options

    * `requeue` - When `true`, the message is requeued. When `false`,
      the message is discarded or sent to a dead letter queue. Defaults to `false`.

  """
  @spec reject(Message.t(), boolean()) :: :ok | error()
  def reject(%Message{} = message, requeue \\ false) do
    adapter().reject(message, requeue)
  end
end
