defmodule FluxWeb.API.PipelineController do
  @moduledoc """
  REST API for pipelines. Every action is scoped to the organization of the
  authenticated API key (`conn.assigns.current_scope`); mutations are gated by
  `Flux.Permissions` via `FluxWeb.API.Authz`.
  """
  use FluxWeb, :controller

  import FluxWeb.API.Authz, only: [authorize: 2, require_scope: 2]

  alias Flux.Pipeline.{Manager, Metrics}
  alias Flux.Pipelines
  alias Flux.Pipelines.PortableConfig

  action_fallback FluxWeb.API.FallbackController

  def index(conn, _params) do
    with :ok <- require_scope(conn, "read:pipelines") do
      pipelines = Pipelines.list_pipelines(org_id(conn))
      render(conn, :index, pipelines: pipelines)
    end
  end

  def show(conn, %{"id" => id}) do
    with :ok <- require_scope(conn, "read:pipelines"),
         {:ok, pipeline} <- fetch(conn, id) do
      metrics =
        Map.get(Metrics.snapshot().per_pipeline, pipeline.id) || metrics_by_string(pipeline.id)

      render(conn, :show, pipeline: pipeline, metrics: metrics)
    end
  end

  def create(conn, params) do
    with :ok <- require_scope(conn, "write:pipelines"),
         :ok <- authorize(conn, :create_pipeline),
         attrs = Map.put(params, "organization_id", org_id(conn)),
         {:ok, pipeline} <- Pipelines.create_pipeline(attrs) do
      conn
      |> put_status(:created)
      |> render(:show, pipeline: pipeline, metrics: nil)
    end
  end

  def export(conn, %{"id" => id}) do
    with :ok <- require_scope(conn, "read:pipelines"),
         {:ok, pipeline} <- fetch(conn, id) do
      envelope = PortableConfig.export_pipeline(pipeline)
      filename = PortableConfig.suggested_filename(pipeline)

      conn
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> json(envelope)
    end
  end

  def import(conn, params) do
    with :ok <- require_scope(conn, "write:pipelines"),
         :ok <- authorize(conn, :create_pipeline),
         {:ok, pipeline} <- PortableConfig.import_pipeline(params, org_id(conn)) do
      conn
      |> put_status(:created)
      |> render(:show, pipeline: pipeline, metrics: nil)
    else
      {:error, {:unsupported_version, version}} ->
        import_error(conn, "unsupported_version", "Unsupported export version: #{version}")

      {:error, {:invalid_format, message}} ->
        import_error(conn, "invalid_format", message)

      {:error, {:invalid_steps, message}} ->
        import_error(conn, "invalid_steps", message)

      {:error, {:missing_sinks, names}} ->
        import_error(
          conn,
          "missing_sinks",
          "Unknown sinks in this organization: #{Enum.join(names, ", ")}"
        )

      other ->
        # {:error, %Ecto.Changeset{}} (incl. name collision) and {:error, :forbidden}
        # are handled by FallbackController.
        other
    end
  end

  def start(conn, %{"id" => id}) do
    with :ok <- require_scope(conn, "write:pipelines"),
         :ok <- authorize(conn, :run_pipeline),
         {:ok, pipeline} <- fetch(conn, id) do
      case Manager.start_pipeline(pipeline.id) do
        {:ok, _pid} ->
          {:ok, pipeline} = Pipelines.update_status(pipeline, "active")
          render(conn, :status, pipeline: pipeline)

        {:error, reason} ->
          transition_error(conn, reason)
      end
    end
  end

  def stop(conn, %{"id" => id}) do
    with :ok <- require_scope(conn, "write:pipelines"),
         :ok <- authorize(conn, :run_pipeline),
         {:ok, pipeline} <- fetch(conn, id) do
      case Manager.stop_pipeline(pipeline.id) do
        :ok ->
          {:ok, pipeline} = Pipelines.update_status(pipeline, "stopped")
          render(conn, :status, pipeline: pipeline)

        {:error, reason} ->
          transition_error(conn, reason)
      end
    end
  end

  defp fetch(conn, id) do
    case Pipelines.get_pipeline(id, org_id(conn)) do
      nil -> {:error, :not_found}
      pipeline -> {:ok, pipeline}
    end
  end

  defp metrics_by_string(id), do: Map.get(Metrics.snapshot().per_pipeline, to_string(id))

  # Pipeline-start safety valve tripped (MOS-450) — too many starts this minute.
  defp transition_error(conn, :rate_limited) do
    conn
    |> put_resp_header("retry-after", "60")
    |> put_status(:too_many_requests)
    |> json(%{
      error: "rate_limited",
      message: "Too many pipeline starts. Try again shortly."
    })
  end

  defp transition_error(conn, reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "transition_failed", message: to_string_reason(reason)})
  end

  defp to_string_reason(reason) when is_binary(reason), do: reason
  defp to_string_reason(reason), do: inspect(reason)

  defp import_error(conn, code, message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: code, message: message})
  end

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
end
