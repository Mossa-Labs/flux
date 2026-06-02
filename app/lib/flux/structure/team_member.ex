defmodule Flux.Structure.TeamMember do
  @moduledoc "Ecto schema for team membership."
  use Ecto.Schema
  import Ecto.Changeset

  schema "team_members" do
    field :role, :string
    field :first_name, :string
    field :last_name, :string
    field :disabled_at, :utc_datetime
    belongs_to :team, Flux.Structure.Team
    belongs_to :user, Flux.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @valid_roles ~w(admin member viewer)

  @doc false
  def changeset(team_member, attrs) do
    team_member
    |> cast(attrs, [:role, :first_name, :last_name, :user_id, :team_id, :disabled_at])
    |> validate_required([:role, :user_id, :team_id])
    |> validate_inclusion(:role, @valid_roles)
  end

  def disabled?(%__MODULE__{disabled_at: nil}), do: false
  def disabled?(%__MODULE__{}), do: true
end
