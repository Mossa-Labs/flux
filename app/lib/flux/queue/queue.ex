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

  @doc """
  Lists messages currently in the dead-letter queue (non-destructive peek).

  Returns `{:error, {:pro_required, :dlq}}` when the active adapter does not
  implement DLQ management (Community's Memory adapter, or the Pro stub).
  """
  @spec list_dlq_messages(non_neg_integer(), non_neg_integer()) ::
          {:ok, [Flux.Queue.Adapter.dlq_message()]} | error()
  def list_dlq_messages(count \\ 50, offset \\ 0) do
    dlq_call(:list_dlq_messages, [count, offset])
  end

  @doc """
  Returns the current depth (message count) of the dead-letter queue.
  """
  @spec dlq_depth() :: {:ok, non_neg_integer()} | error()
  def dlq_depth do
    dlq_call(:get_dlq_depth, [])
  end

  @doc """
  Re-publishes a dead-lettered message back to its original queue and
  removes it from the DLQ.
  """
  @spec retry_message(term()) :: :ok | error()
  def retry_message(delivery_tag) do
    dlq_call(:retry_message, [delivery_tag])
  end

  @doc """
  Permanently removes a message from the dead-letter queue.
  """
  @spec discard_message(term()) :: :ok | error()
  def discard_message(delivery_tag) do
    dlq_call(:discard_message, [delivery_tag])
  end

  # DLQ callbacks are optional on the adapter behaviour. Guard with
  # function_exported?/3 so an adapter that omits them (e.g. Memory) yields a
  # clean upgrade-prompt error instead of an UndefinedFunctionError.
  defp dlq_call(fun, args) do
    mod = adapter()

    if function_exported?(mod, fun, length(args)) do
      apply(mod, fun, args)
    else
      {:error, {:pro_required, :dlq}}
    end
  end
end
