defmodule Flux.Security.SecuritySettings do
  @moduledoc """
  Per-organization security settings (MOS-588).

  A single row per organization holding application-layer security policy:
  `ip_allowlist` (CIDR ranges allowed to reach the API; empty = no restriction),
  `session_timeout_minutes` (idle session timeout; default 30d, min 1h), and the
  password policy (MOS-590): minimum length, character-class complexity, and
  rotation. The password policy is only enforced when the `:password_policy`
  feature is entitled; ungated builds keep the min-12 default.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Flux.Structure.Organization

  @type t :: %__MODULE__{}

  # Minimum idle session timeout: 1 hour.
  @min_session_timeout_minutes 60

  # Community password floor. A policy can raise the minimum length but never
  # lower it below this — the base rule stays enforced even when entitled.
  @min_password_length 12

  schema "security_settings" do
    field :ip_allowlist, {:array, :string}, default: []
    field :session_timeout_minutes, :integer, default: 43_200

    field :password_min_length, :integer, default: 12
    field :password_require_upper, :boolean, default: false
    field :password_require_lower, :boolean, default: false
    field :password_require_number, :boolean, default: false
    field :password_require_special, :boolean, default: false
    field :password_rotation_days, :integer

    # Per-org "require MFA for all members" (MOS-591). Only enforced when the
    # :mfa_enforcement feature is entitled; ungated builds keep it off.
    field :require_mfa, :boolean, default: false

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc "The Community password floor (minimum length a policy may not go below)."
  def min_password_length, do: @min_password_length

  @doc false
  def changeset(settings, attrs) do
    settings
    # organization_id is set programmatically (via the context), never cast.
    |> cast(attrs, [
      :ip_allowlist,
      :session_timeout_minutes,
      :password_min_length,
      :password_require_upper,
      :password_require_lower,
      :password_require_number,
      :password_require_special,
      :password_rotation_days,
      :require_mfa
    ])
    |> validate_required([:organization_id, :session_timeout_minutes, :password_min_length])
    |> validate_number(:session_timeout_minutes,
      greater_than_or_equal_to: @min_session_timeout_minutes
    )
    # A policy can raise the minimum length but never weaken the Community floor.
    |> validate_number(:password_min_length, greater_than_or_equal_to: @min_password_length)
    |> validate_number(:password_rotation_days, greater_than: 0)
    |> normalize_cidrs()
    |> validate_cidrs()
    |> unique_constraint(:organization_id)
    |> foreign_key_constraint(:organization_id)
  end

  # Trim blanks and expand a bare IP to a full-length CIDR so operators can type
  # "1.2.3.4" instead of "1.2.3.4/32".
  defp normalize_cidrs(changeset) do
    case fetch_change(changeset, :ip_allowlist) do
      {:ok, values} when is_list(values) ->
        normalized =
          values
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&normalize_entry/1)

        put_change(changeset, :ip_allowlist, normalized)

      _ ->
        changeset
    end
  end

  defp normalize_entry(entry) do
    cond do
      String.contains?(entry, "/") -> entry
      String.contains?(entry, ":") -> entry <> "/128"
      true -> entry <> "/32"
    end
  end

  defp validate_cidrs(changeset) do
    validate_change(changeset, :ip_allowlist, fn :ip_allowlist, values ->
      case Enum.reject(values, &valid_cidr?/1) do
        [] -> []
        bad -> [ip_allowlist: "invalid CIDR range(s): #{Enum.join(bad, ", ")}"]
      end
    end)
  end

  defp valid_cidr?(entry) when is_binary(entry) do
    InetCidr.parse_cidr!(entry)
    true
  rescue
    _ -> false
  end

  defp valid_cidr?(_), do: false
end
