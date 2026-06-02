defmodule Flux.Structure.OrganizationMember do
  @moduledoc """
  Organization membership and role (used when :rbac_mode is :org_centric).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @valid_roles ~w(owner admin member viewer)

  schema "organization_members" do
    field :role, :string
    field :disabled_at, :utc_datetime
    belongs_to :organization, Flux.Structure.Organization
    belongs_to :user, Flux.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(organization_member, attrs) do
    organization_member
    |> cast(attrs, [:organization_id, :user_id, :role, :disabled_at])
    |> validate_required([:organization_id, :user_id, :role])
    |> validate_inclusion(:role, @valid_roles)
    |> unique_constraint([:organization_id, :user_id])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
  end

  def disabled?(%__MODULE__{disabled_at: nil}), do: false
  def disabled?(%__MODULE__{}), do: true
end
