defmodule Flux.Structure.Team do
  @moduledoc "Ecto schema for teams within an organization."
  use Ecto.Schema
  import Ecto.Changeset

  alias Flux.Accounts.Scope

  schema "teams" do
    field :name, :string
    field :description, :string
    field :organization_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(team, attrs, user_scope) do
    team
    |> cast(attrs, [:name, :description, :organization_id])
    |> validate_required([:name])
    |> put_organization_id(user_scope)
    |> put_change(:user_id, user_scope.user.id)
  end

  defp put_organization_id(changeset, %Scope{organization_id: org_id}) when is_integer(org_id) do
    put_change(changeset, :organization_id, org_id)
  end

  defp put_organization_id(changeset, _scope), do: changeset
end
