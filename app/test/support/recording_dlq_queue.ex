defmodule Flux.Test.RecordingDlqQueue do
  @moduledoc """
  Queue adapter double for testing the `Flux.Queue` facade.

  It implements `producer_spec/1` but not `message_organization_id/1`, so it
  also stands in for an adapter that can't attribute consumed messages.
  """
  @behaviour Flux.Queue.Adapter

  @impl true
  def publish(_queue, _message, _opts), do: :ok

  @impl true
  def ack(_message), do: :ok

  @impl true
  def reject(_message, _requeue), do: :ok

  @impl true
  def producer_spec(opts), do: {Flux.Pipeline.Producers.Memory, opts}
end
