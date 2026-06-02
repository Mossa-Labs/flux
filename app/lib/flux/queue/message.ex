defmodule Flux.Queue.Message do
  @moduledoc """
  Represents a message in the queue system.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          payload: map(),
          source: String.t(),
          correlation_id: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t(),
          adapter_meta: map()
        }

  @enforce_keys [:id, :payload, :source, :inserted_at]
  defstruct [
    :id,
    :payload,
    :source,
    :correlation_id,
    :inserted_at,
    metadata: %{},
    adapter_meta: %{}
  ]

  @doc """
  Creates a new message with the given payload.

  ## Options

    * `:source` - The source identifier (default: "unknown")
    * `:correlation_id` - Optional correlation ID for tracing
    * `:metadata` - Additional metadata map

  ## Examples

      iex> Flux.Queue.Message.new(%{event: "user.created"}, source: "webhook")
      %Flux.Queue.Message{payload: %{event: "user.created"}, source: "webhook", ...}

  """
  @spec new(map(), keyword()) :: t()
  def new(payload, opts \\ []) when is_map(payload) do
    %__MODULE__{
      id: generate_id(),
      payload: payload,
      source: Keyword.get(opts, :source, "unknown"),
      correlation_id: Keyword.get(opts, :correlation_id),
      metadata: Keyword.get(opts, :metadata, %{}),
      inserted_at: DateTime.utc_now()
    }
  end

  defp generate_id do
    Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
end
