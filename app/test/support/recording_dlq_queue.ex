defmodule Flux.Test.RecordingDlqQueue do
  @moduledoc """
  Queue adapter double for testing the `Flux.Queue` facade.

  Every DLQ callback reports `{:dlq_call, callback, args}` to the calling
  process (the facade calls adapters synchronously), so a test can assert what
  the adapter was asked for. `list_dlq_messages/3` returns the dead letters the
  test put in its process dictionary under `:recording_dlq_messages`.

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

  @impl true
  def list_dlq_messages(org_id, count, offset) do
    report(:list_dlq_messages, [org_id, count, offset])
    {:ok, Process.get(:recording_dlq_messages, [])}
  end

  @impl true
  def get_dlq_depth(org_id) do
    report(:get_dlq_depth, [org_id])
    {:ok, 3}
  end

  @impl true
  def retry_message(org_id, delivery_tag) do
    report(:retry_message, [org_id, delivery_tag])
    :ok
  end

  @impl true
  def discard_message(org_id, delivery_tag) do
    report(:discard_message, [org_id, delivery_tag])
    :ok
  end

  @impl true
  def replay_dlq(org_id, filters, limit) do
    report(:replay_dlq, [org_id, filters, limit])
    {:ok, %{replayed: 0, skipped: 0, exhausted?: true}}
  end

  defp report(callback, args), do: send(self(), {:dlq_call, callback, args})
end
