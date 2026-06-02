defmodule Flux.Pipelines do
  @moduledoc """
  The Pipelines context manages pipeline configurations and lifecycle.
  """

  import Ecto.Query, warn: false
  alias Flux.Repo
  alias Flux.Pipelines.Pipeline

  @doc """
  Returns the list of pipelines for an organization.

  ## Examples

      iex> list_pipelines(organization_id)
      [%Pipeline{}, ...]

  """
  def list_pipelines(organization_id) do
    Pipeline
    |> where([p], p.organization_id == ^organization_id)
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Returns all active pipelines across all organizations.
  Used for auto-starting pipelines on application boot.
  """
  def list_active_pipelines do
    Pipeline
    |> where([p], p.status == "active")
    |> Repo.all()
  end

  @doc """
  Gets a single pipeline.

  Raises `Ecto.NoResultsError` if the Pipeline does not exist.

  ## Examples

      iex> get_pipeline!(123)
      %Pipeline{}

      iex> get_pipeline!(456)
      ** (Ecto.NoResultsError)

  """
  def get_pipeline!(id), do: Repo.get!(Pipeline, id)

  @doc """
  Gets a single pipeline by id and organization.

  Returns nil if not found.
  """
  def get_pipeline(id, organization_id) do
    Pipeline
    |> where([p], p.id == ^id and p.organization_id == ^organization_id)
    |> Repo.one()
  end

  @doc """
  Creates a pipeline.

  ## Examples

      iex> create_pipeline(%{field: value})
      {:ok, %Pipeline{}}

      iex> create_pipeline(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_pipeline(attrs \\ %{}) do
    %Pipeline{}
    |> Pipeline.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a pipeline.

  ## Examples

      iex> update_pipeline(pipeline, %{field: new_value})
      {:ok, %Pipeline{}}

      iex> update_pipeline(pipeline, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_pipeline(%Pipeline{} = pipeline, attrs) do
    pipeline
    |> Pipeline.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the pipeline status.
  """
  def update_status(%Pipeline{} = pipeline, status) when status in ~w(active paused stopped) do
    update_pipeline(pipeline, %{status: status})
  end

  @doc """
  Deletes a pipeline.

  ## Examples

      iex> delete_pipeline(pipeline)
      {:ok, %Pipeline{}}

      iex> delete_pipeline(pipeline)
      {:error, %Ecto.Changeset{}}

  """
  def delete_pipeline(%Pipeline{} = pipeline) do
    Repo.delete(pipeline)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking pipeline changes.

  ## Examples

      iex> change_pipeline(pipeline)
      %Ecto.Changeset{data: %Pipeline{}}

  """
  def change_pipeline(%Pipeline{} = pipeline, attrs \\ %{}) do
    Pipeline.changeset(pipeline, attrs)
  end
end
