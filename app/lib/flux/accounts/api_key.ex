defmodule Flux.Accounts.ApiKey do
  @moduledoc """
  Per-organization API key.

  Only a SHA-256 hash of the key is stored (`key_hash`); the plaintext
  (`flux_pk_<32 base62>`) is returned exactly once at creation. `key_prefix`
  is the displayable head of the key, safe to show in UIs and logs.

  Each key carries a coarse `role` (`admin | member | viewer`) that the API
  authorization layer evaluates via `Flux.Permissions.can?/2`.

  TODO(api-key-scopes): replace the single coarse `role` with fine-grained,
  OAuth-style resource scopes (e.g. `read:pipelines`, `write:sinks`) chosen at
  creation. Tracked in the backlog (see MOS-456 plan, Phase 5).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(admin member viewer)

  schema "api_keys" do
    field :key_prefix, :string
    field :key_hash, :string
    field :name, :string
    field :role, :string, default: "admin"
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :organization, Flux.Structure.Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a new key. `key_prefix`, `key_hash`, and `organization_id` are
  set programmatically by the context, never cast from user input.
  """
  def create_changeset(api_key, attrs, programmatic) do
    api_key
    |> cast(attrs, [:name, :role, :expires_at])
    |> validate_required([:name])
    |> validate_inclusion(:role, @roles)
    |> put_change(:key_prefix, programmatic.key_prefix)
    |> put_change(:key_hash, programmatic.key_hash)
    |> put_change(:organization_id, programmatic.organization_id)
    |> unique_constraint(:key_hash)
    |> foreign_key_constraint(:organization_id)
  end

  @doc "The roles a key may be assigned (owner is intentionally human-only)."
  def roles, do: @roles

  @doc "Whether the key is currently usable (not revoked and not expired)."
  def active?(%__MODULE__{} = key, now \\ DateTime.utc_now()) do
    not revoked?(key) and not expired?(key, now)
  end

  def revoked?(%__MODULE__{revoked_at: nil}), do: false
  def revoked?(%__MODULE__{}), do: true

  def expired?(%__MODULE__{expires_at: nil}, _now), do: false

  def expired?(%__MODULE__{expires_at: expires_at}, now),
    do: DateTime.compare(now, expires_at) == :gt
end
