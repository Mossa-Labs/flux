defmodule Flux.Test.LoopbackQueue do
  @moduledoc """
  Test queue adapter that hands every published message straight to the Memory
  producers consuming that queue, so a test can drive the whole path: ingest
  (webhook, poller, a pipeline's destination) → queue → running pipeline.

  The Memory adapter stores published messages but doesn't deliver them to
  pipelines yet. Once it does, tests can use it directly and this adapter can go.

  Register it as the active adapter for the duration of a test:

      Flux.Queue.Registry.register("loopback", Flux.Test.LoopbackQueue)
      Flux.Queue.Registry.set_active("loopback")
      on_exit(fn -> Flux.Queue.Registry.set_active("memory") end)
  """
  @behaviour Flux.Queue.Adapter

  alias Flux.Pipeline.Producers.Memory, as: MemoryProducer
  alias Flux.Queue.Adapters.Memory
  alias Flux.Queue.Naming

  @impl true
  def publish(queue, message, _opts) do
    with :ok <- Naming.check_owner(queue, message.organization_id) do
      MemoryProducer.deliver(to_string(queue), message)
    end
  end

  @impl true
  def ack(_message), do: :ok

  @impl true
  def reject(_message, _requeue), do: :ok

  @impl true
  def producer_spec(opts), do: Memory.producer_spec(opts)

  @impl true
  def message_organization_id(message), do: Memory.message_organization_id(message)
end
