defmodule Flux.Security do
  @moduledoc """
  The Security context: per-organization application-layer security settings
  (MOS-588).

  Exposes the IP allowlist — per-org CIDR ranges permitted to reach the
  authenticated API (empty = no restriction; enforced in
  `FluxWeb.Plugs.IpAllowlist`) — and the per-org idle **session timeout**
  (`session_timeout_minutes/1`, enforced in `FluxWeb.UserAuth`). Both hot-path
  reads are served from a short-lived cache (`Flux.Security.Cache`).
  """

  import Ecto.Query, warn: false

  alias Flux.Repo
  alias Flux.Security.{Cache, SecuritySettings}

  @default_session_timeout_minutes 43_200

  @doc """
  Returns the org's security settings, or an unsaved default (empty allowlist)
  when none exist yet.
  """
  @spec get_settings(term()) :: SecuritySettings.t()
  def get_settings(org_id) do
    Repo.get_by(SecuritySettings, organization_id: org_id) ||
      %SecuritySettings{organization_id: org_id, ip_allowlist: []}
  end

  @doc "Changeset for the security-settings form."
  def change_settings(%SecuritySettings{} = settings, attrs \\ %{}) do
    SecuritySettings.changeset(settings, attrs)
  end

  @doc """
  Creates or updates an org's security settings, then evicts the allowlist cache
  and records an audit event. Returns `{:ok, settings}` or `{:error, changeset}`.
  """
  @spec update_settings(term(), map()) ::
          {:ok, SecuritySettings.t()} | {:error, Ecto.Changeset.t()}
  def update_settings(org_id, attrs) do
    org_id
    |> get_settings()
    |> SecuritySettings.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, settings} ->
        Cache.bust(org_id)

        Flux.Audit.log(%{
          organization_id: org_id,
          action: :security_settings_updated,
          resource_type: :organization,
          resource_id: org_id,
          changes: %{
            "ip_allowlist" => settings.ip_allowlist,
            "session_timeout_minutes" => settings.session_timeout_minutes,
            "require_mfa" => settings.require_mfa
          }
        })

        {:ok, settings}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Whether `ip` (an `:inet` address tuple, e.g. `conn.remote_ip`) may access the
  org's API. An empty allowlist allows everything; otherwise the IP must fall
  within one of the configured CIDR ranges.
  """
  @spec ip_allowed?(term(), :inet.ip_address()) :: boolean()
  def ip_allowed?(org_id, ip) when is_tuple(ip) do
    case cached(org_id).allowlist do
      [] -> true
      cidrs -> Enum.any?(cidrs, &InetCidr.contains?(&1, ip))
    end
  end

  @doc """
  The org's idle session timeout in minutes (default 30 days). Served from the
  cache; `nil` org (no organization in scope) yields the default.
  """
  @spec session_timeout_minutes(term()) :: pos_integer()
  def session_timeout_minutes(nil), do: @default_session_timeout_minutes
  def session_timeout_minutes(org_id), do: cached(org_id).timeout_minutes

  @doc """
  Whether the org requires every member to have MFA enabled. Served from the
  cache; `nil` org (no organization in scope) is never required.

  This reflects the stored per-org toggle only — entitlement gating lives in
  `Flux.Accounts.MfaEnforcement`, which must be consulted for the effective
  decision so a license downgrade can't lock members out.
  """
  @spec require_mfa?(term()) :: boolean()
  def require_mfa?(nil), do: false
  def require_mfa?(org_id), do: cached(org_id).require_mfa

  # Cached, derived view of an org's settings for the hot paths: parsed CIDR
  # tuples + resolved timeout + MFA-required flag. One DB read populates all;
  # busted on update.
  defp cached(org_id) do
    Cache.fetch(org_id, fn ->
      settings = get_settings(org_id)

      %{
        allowlist: Enum.flat_map(settings.ip_allowlist, &parse_cidr/1),
        timeout_minutes: settings.session_timeout_minutes || @default_session_timeout_minutes,
        require_mfa: settings.require_mfa || false
      }
    end)
  end

  defp parse_cidr(cidr) do
    [InetCidr.parse_cidr!(cidr)]
  rescue
    _ -> []
  end
end
