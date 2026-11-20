defmodule Flux.Queue do
  @moduledoc """
  Facade for queue adapters. The adapter contract lives in `Flux.Queue.Adapter`.

  Adapters are registered at boot against a string type identifier in
  `Flux.Queue.Registry`; the configured `:active` queue type (set via
  `config :flux, Flux.Queue, type: "memory"`) is resolved on each call.

  ## Organizations

  Every queue belongs to one organization. Callers pass the organization and a
  *logical* queue name; this module is the one place that turns them into the
  *physical* queue an adapter uses (see `Flux.Queue.Naming`), so a caller can
  never reach another organization's queue. Callers always take the
  organization from the server (an API key, a pipeline, a source), never from
  user input.

  Logical names are all a tenant ever sees.

  ## Usage

      alias Flux.Queue
      alias Flux.Queue.Message

      message = Message.new(%{event: "user.created", data: %{id: 1}}, source: "webhook")
      :ok = Queue.publish(organization_id, "webhooks.github", message, [])

  """

  alias Flux.Queue.Message
  alias Flux.Queue.Naming

  @type organization_id :: Flux.Queue.Adapter.organization_id()
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
  Publishes `message` to the logical queue `queue` of organization `org_id`.

  The message is stamped with `org_id` and published to the organization's
  physical queue. Returns:

    * `{:error, :organization_required}` when `org_id` isn't a valid id.
    * `{:error, :organization_mismatch}` when the message already names a
      different organization.
    * `{:error, {:invalid_queue, reason}}` when `queue` isn't a valid logical
      name (see `Flux.Queue.Naming.validate_logical/1`).

  ## Examples

      message = Flux.Queue.Message.new(%{event: "test"}, source: "api")
      :ok = Flux.Queue.publish(organization_id, "events", message, [])

  """
  @spec publish(organization_id(), String.t(), Message.t(), publish_opts()) :: :ok | error()
  def publish(org_id, queue, %Message{} = message, opts) do
    with :ok <- check_message_org(message, org_id),
         {:ok, physical} <- physical(org_id, queue) do
      adapter().publish(physical, %{message | organization_id: org_id}, opts)
    end
  end

  @doc """
  Returns the Broadway producer module and options that consume the logical
  queue `queue` of organization `org_id`, for `Flux.Pipeline.Runner`.

  `opts` (`:pipeline_id`, `:prefetch_count`) are passed through to the adapter.
  Returns `{:error, :adapter_cannot_attribute_messages}` if the active adapter
  can't report a consumed message's organization, so a pipeline never starts
  on a queue whose messages it would have to refuse.
  """
  @spec producer_spec(organization_id(), String.t(), keyword()) ::
          {:ok, {module(), keyword()}} | error()
  def producer_spec(org_id, queue, opts) do
    mod = adapter()

    cond do
      not exports?(mod, :producer_spec, 1) ->
        {:error, :adapter_cannot_consume}

      not exports?(mod, :message_organization_id, 1) ->
        {:error, :adapter_cannot_attribute_messages}

      true ->
        with {:ok, physical} <- physical(org_id, queue) do
          {:ok, mod.producer_spec(Keyword.merge(opts, queue: physical, organization_id: org_id))}
        end
    end
  end

  @doc """
  The organization a consumed Broadway message was published for, as reported
  by `adapter` (the adapter whose producer emitted it).
  """
  @spec message_organization_id(module(), Broadway.Message.t()) ::
          {:ok, organization_id()} | :error
  def message_organization_id(adapter, %Broadway.Message{} = message) do
    if exports?(adapter, :message_organization_id, 1) do
      case adapter.message_organization_id(message) do
        {:ok, id} when is_integer(id) and id > 0 -> {:ok, id}
        _ -> :error
      end
    else
      :error
    end
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

  @doc """
  Bulk-replays up to `limit` dead-lettered messages matching `filters` back to
  their original queues. Non-matching messages are left in the DLQ.

  Drives one batch; `Flux.Workers.ReplayWorker` loops until the returned
  `exhausted?` flag is `true`. Returns `{:error, {:pro_required, :dlq}}` when the
  active adapter does not implement DLQ replay.
  """
  @spec replay_dlq(Flux.Queue.Adapter.replay_filters(), pos_integer()) ::
          {:ok, Flux.Queue.Adapter.replay_result()} | error()
  def replay_dlq(filters, limit) do
    dlq_call(:replay_dlq, [filters, limit])
  end

  defp physical(org_id, queue) do
    case Naming.physical(org_id, queue) do
      {:ok, physical} -> {:ok, physical}
      {:error, :organization_required} -> {:error, :organization_required}
      {:error, reason} -> {:error, {:invalid_queue, reason}}
    end
  end

  defp check_org(org_id) when is_integer(org_id) and org_id > 0, do: :ok
  defp check_org(_org_id), do: {:error, :organization_required}

  defp check_message_org(%Message{organization_id: nil}, org_id), do: check_org(org_id)
  defp check_message_org(%Message{organization_id: org_id}, org_id), do: check_org(org_id)
  defp check_message_org(%Message{}, _org_id), do: {:error, :organization_mismatch}

  # DLQ callbacks are optional on the adapter behaviour. Guard with
  # exports?/3 so an adapter that omits them (e.g. Memory) yields a clean
  # upgrade-prompt error instead of an UndefinedFunctionError.
  defp dlq_call(fun, args) do
    mod = adapter()

    if exports?(mod, fun, length(args)) do
      apply(mod, fun, args)
    else
      {:error, {:pro_required, :dlq}}
    end
  end

  # `function_exported?/3` is false for a module that isn't loaded yet, which
  # would make an implemented optional callback look missing.
  defp exports?(mod, fun, arity) do
    is_atom(mod) and Code.ensure_loaded?(mod) and function_exported?(mod, fun, arity)
  end
end
