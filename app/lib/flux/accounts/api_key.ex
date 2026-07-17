defmodule Flux.Accounts.ApiKey do
  @moduledoc """
  Per-organization API key.

  Only a SHA-256 hash of the key is stored (`key_hash`); the plaintext
  (`flux_pk_<32 base62>`) is returned exactly once at creation. `key_prefix`
  is the displayable head of the key, safe to show in UIs and logs.

  A key carries two authorization dimensions:

    * `role` (`admin | member | viewer`) — the coarse org role, evaluated by
      `Flux.Permissions.can?/2` (caps what the key can ever do);
    * `scopes` — OAuth-style resource grants (e.g. `read:pipelines`,
      `write:sinks`) for least-privilege automation.

  A request is allowed only when **both** pass — scopes can narrow a key below
  its role but never widen it past it. Scopes default to the full set implied by
  the role; a key persisted before scopes existed (empty `scopes`) is treated as
  the role's full set via `effective_scopes/1`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(admin member viewer)
  @scopes ~w(read:pipelines write:pipelines read:sinks write:sinks read:usage read:audit_logs)
  @viewer_scopes ~w(read:pipelines read:sinks read:usage)

  schema "api_keys" do
    field :key_prefix, :string
    field :key_hash, :string
    field :name, :string
    field :role, :string, default: "admin"
    field :scopes, {:array, :string}, default: []
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :organization, Flux.Structure.Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a new key. `key_prefix`, `key_hash`, and `organization_id` are
  set programmatically by the context, never cast from user input. When no
  scopes are supplied, the role's default set is applied.
  """
  def create_changeset(api_key, attrs, programmatic) do
    api_key
    |> cast(attrs, [:name, :role, :expires_at, :scopes])
    |> validate_required([:name])
    |> validate_inclusion(:role, @roles)
    |> validate_subset(:scopes, @scopes)
    |> put_default_scopes()
    |> put_change(:key_prefix, programmatic.key_prefix)
    |> put_change(:key_hash, programmatic.key_hash)
    |> put_change(:organization_id, programmatic.organization_id)
    |> unique_constraint(:key_hash)
    |> foreign_key_constraint(:organization_id)
  end

  defp put_default_scopes(changeset) do
    case get_field(changeset, :scopes) do
      scopes when scopes in [nil, []] ->
        put_change(changeset, :scopes, default_scopes_for_role(get_field(changeset, :role)))

      _ ->
        changeset
    end
  end

  @doc "The roles a key may be assigned (owner is intentionally human-only)."
  def roles, do: @roles

  @doc "All assignable scopes."
  def scopes, do: @scopes

  @doc "The default scopes implied by a role."
  def default_scopes_for_role("viewer"), do: @viewer_scopes
  def default_scopes_for_role(_role), do: @scopes

  @doc """
  The scopes a key effectively grants. Falls back to the role's full set when
  `scopes` is empty (rows created before scopes existed).
  """
  def effective_scopes(%__MODULE__{scopes: scopes, role: role}) do
    case scopes do
      list when is_list(list) and list != [] -> list
      _ -> default_scopes_for_role(role)
    end
  end

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
