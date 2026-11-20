defmodule Flux.Workers.Poller do
  @moduledoc """
  Oban worker that polls external sources on a schedule.

  This is a skeleton implementation. Each polling source should be
  configured with:

    * URL to poll
    * Frequency (cron expression or interval)
    * Authentication method
    * Data transformation rules

  ## Usage

  To schedule a polling job:

      %{
        "source_id" => "my-source",
        "organization_id" => organization_id,
        "url" => "https://api.example.com/data"
      }
      |> Flux.Workers.Poller.new(schedule_in: 60)
      |> Oban.insert()

  `organization_id` is required: the polled data is queued in that
  organization's `polling.<source_id>` queue, and only its pipelines can
  consume it. A job without a valid organization is cancelled. Jobs are only
  ever built on the server, which takes the organization from the source it
  polls for, never from user input.

  """

  use Oban.Worker,
    queue: :polling,
    max_attempts: 3,
    unique: [period: 60, states: [:available, :scheduled, :executing]]

  import Ecto.Query, only: [from: 2]

  alias Flux.Queue
  alias Flux.Queue.Message
  alias Flux.Repo
  alias Flux.Structure.Organization

  require Logger

  # Note: scheduled (cron) polling is the `:cron_polling` Pro feature. The gate
  # lives where the recurring schedule is configured — the `Oban.Plugins.Cron`
  # plugin is only wired up in licensed (Pro/Enterprise) builds.
  # This worker stays ungated so one-off jobs enqueued directly still run.
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source_id = Map.fetch!(args, "source_id")
    url = Map.get(args, "url")

    # Queue-name convention is owned by the Poll source adapter (see
    # Flux.Source.Adapters.Poll) so all ingestion paths share one definition.
    # The name is logical; Flux.Queue places it in the job's organization.
    queue_name = Flux.Source.queue_name("poll", %{"source_id" => source_id})

    with {:ok, org_id} <- organization(args),
         :ok <- valid_queue(queue_name) do
      Logger.info("Polling source", source_id: source_id, url: url)
      poll(org_id, source_id, queue_name, url, args)
    else
      {:cancel, reason} = cancel ->
        Logger.error("Poll cancelled", source_id: source_id, reason: inspect(reason))
        cancel
    end
  end

  defp organization(%{"organization_id" => id}) when is_integer(id) and id > 0 do
    if Repo.exists?(from(o in Organization, where: o.id == ^id)),
      do: {:ok, id},
      else: {:cancel, :organization_not_found}
  end

  defp organization(_args), do: {:cancel, :organization_required}

  defp valid_queue(queue_name) do
    case Flux.Queue.Naming.validate_logical(queue_name) do
      :ok -> :ok
      {:error, reason} -> {:cancel, {:invalid_queue, reason}}
    end
  end

  defp poll(org_id, source_id, queue_name, url, args) do
    with {:ok, data} <- fetch_data(url, args),
         message <- build_message(source_id, data),
         :ok <- Queue.publish(org_id, queue_name, message, []) do
      Logger.info("Poll completed successfully",
        source_id: source_id,
        message_id: message.id
      )

      :ok
    else
      {:error, reason} = error ->
        Logger.error("Poll failed",
          source_id: source_id,
          reason: inspect(reason)
        )

        error
    end
  end

  defp fetch_data(nil, _args) do
    # No URL configured - return placeholder data for skeleton implementation
    {:ok, %{placeholder: true, fetched_at: DateTime.utc_now() |> DateTime.to_iso8601()}}
  end

  defp fetch_data(url, args) do
    headers = args |> Map.get("headers", %{}) |> Map.to_list()

    # Using Req as specified in CLAUDE.md guidelines
    case Req.get(url, headers: headers) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, exception} ->
        {:error, {:request_failed, exception}}
    end
  end

  defp build_message(source_id, data) do
    Message.new(data,
      source: "poller:#{source_id}",
      metadata: %{
        poll_type: "scheduled",
        polled_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    )
  end
end
