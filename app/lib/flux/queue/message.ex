defmodule Flux.Queue.Message do
  @moduledoc """
  Represents a message in the queue system.

  `organization_id` names the organization the message belongs to. Every
  message published through `Flux.Queue.publish/4` carries one, and a pipeline
  refuses a message that doesn't carry its own organization.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          payload: map(),
          source: String.t(),
          organization_id: pos_integer() | nil,
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
    :organization_id,
    :correlation_id,
    :inserted_at,
    metadata: %{},
    adapter_meta: %{}
  ]

  @doc """
  Creates a new message with the given payload.

  ## Options

    * `:source` - The source identifier (default: "unknown")
    * `:organization_id` - The organization the message belongs to. `Flux.Queue.publish/4`
      sets it from its own argument, so publishers don't have to.
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
      organization_id: Keyword.get(opts, :organization_id),
      correlation_id: Keyword.get(opts, :correlation_id),
      metadata: Keyword.get(opts, :metadata, %{}),
      inserted_at: DateTime.utc_now()
    }
  end

  defp generate_id do
    Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
end
