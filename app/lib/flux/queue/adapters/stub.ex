defmodule Flux.Queue.Adapters.Stub do
  @moduledoc """
  Placeholder queue adapter registered against Pro-only queue types
  (RabbitMQ, Kafka) in Community builds.

  Exposes `start_link/1` so it can occupy a supervision child slot if
  selected as the active queue — but it logs a warning and rejects all
  publish/ack/reject operations with `{:error, {:pro_required, _}}`.
  """

  use GenServer

  @behaviour Flux.Queue.Adapter

  require Logger

  alias Flux.Queue.Message

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl Flux.Queue.Adapter
  def publish(_queue, %Message{} = _message, _opts \\ []), do: pro_required()

  @impl Flux.Queue.Adapter
  def ack(%Message{} = _message), do: pro_required()

  @impl Flux.Queue.Adapter
  def reject(%Message{} = _message, _requeue \\ false), do: pro_required()

  @impl Flux.Queue.Adapter
  def producer_spec(_opts) do
    raise "Active queue type requires Flux Pro. Configure `config :flux, Flux.Queue, type: \"memory\"` for Community, or upgrade to Pro to use RabbitMQ/Kafka."
  end

  @impl Flux.Queue.Adapter
  def list_dlq_messages(_count, _offset), do: dlq_required()

  @impl Flux.Queue.Adapter
  def get_dlq_depth, do: dlq_required()

  @impl Flux.Queue.Adapter
  def retry_message(_delivery_tag), do: dlq_required()

  @impl Flux.Queue.Adapter
  def discard_message(_delivery_tag), do: dlq_required()

  @impl Flux.Queue.Adapter
  def replay_dlq(_filters, _limit), do: dlq_required()

  @impl GenServer
  def init(opts) do
    feature = Keyword.get(opts, :feature, :pro_queue)

    Logger.warning(
      "[Flux.Queue.Adapters.Stub] Pro queue backend not available in Community builds (feature: #{inspect(feature)}). Publish/ack/reject will return {:error, {:pro_required, ...}}."
    )

    {:ok, %{feature: feature}}
  end

  defp pro_required, do: {:error, {:pro_required, :pro_queue}}

  defp dlq_required, do: {:error, {:pro_required, :dlq}}
end
