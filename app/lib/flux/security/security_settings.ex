defmodule Flux.Security.SecuritySettings do
  @moduledoc """
  Per-organization security settings (MOS-588).

  A single row per organization holding application-layer security policy.
  Currently: `ip_allowlist`, a list of CIDR ranges allowed to reach the API
  (empty = no restriction). This table is the shared home for later security
  policy — session timeout, password policy — added by their own slices.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Flux.Structure.Organization

  @type t :: %__MODULE__{}

  schema "security_settings" do
    field :ip_allowlist, {:array, :string}, default: []

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settings, attrs) do
    settings
    # organization_id is set programmatically (via the context), never cast.
    |> cast(attrs, [:ip_allowlist])
    |> validate_required([:organization_id])
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
