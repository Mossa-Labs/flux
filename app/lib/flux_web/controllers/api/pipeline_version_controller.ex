defmodule FluxWeb.API.PipelineVersionController do
  @moduledoc """
  REST API for pipeline version history and rollback. Scoped to the organization
  of the authenticated API key; rollback is gated by `Flux.Permissions` via
  `FluxWeb.API.Authz`.
  """
  use FluxWeb, :controller

  import FluxWeb.API.Authz, only: [authorize: 2, require_scope: 2]

  alias Flux.Pipelines

  action_fallback FluxWeb.API.FallbackController

  def index(conn, %{"id" => id}) do
    with :ok <- require_scope(conn, "read:pipelines"),
         {:ok, pipeline} <- fetch(conn, id) do
      versions = Pipelines.list_pipeline_versions(pipeline.id)
      render(conn, :index, versions: versions)
    end
  end

  def rollback(conn, %{"id" => id} = params) do
    with :ok <- require_scope(conn, "write:pipelines"),
         :ok <- authorize(conn, :edit_pipeline),
         {:ok, pipeline} <- fetch(conn, id),
         {:ok, version} <- parse_version(params),
         {:ok, pipeline} <-
           Pipelines.rollback_pipeline(pipeline, version, actor_id: actor_id(conn)) do
      render(conn, :pipeline, pipeline: pipeline)
    else
      {:error, :version_not_found} ->
        {:error, :not_found}

      {:error, :invalid_version} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_version", message: "A valid integer `version` is required."})

      other ->
        other
    end
  end

  defp fetch(conn, id) do
    case Pipelines.get_pipeline(id, org_id(conn)) do
      nil -> {:error, :not_found}
      pipeline -> {:ok, pipeline}
    end
  end

  defp parse_version(%{"version" => v}) when is_integer(v), do: {:ok, v}

  defp parse_version(%{"version" => v}) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :invalid_version}
    end
  end

  defp parse_version(_), do: {:error, :invalid_version}

  defp org_id(conn), do: conn.assigns.current_scope.organization_id

  defp actor_id(conn) do
    case conn.assigns.current_scope.user do
      %{id: id} -> id
      _ -> nil
    end
  end
end
