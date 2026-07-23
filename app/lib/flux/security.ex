defmodule Flux.Security do
  @moduledoc """
  The Security context: per-organization application-layer security settings
  (MOS-588).

  Currently exposes the IP allowlist — per-org CIDR ranges permitted to reach
  the authenticated API. An empty allowlist means no restriction. Enforcement
  lives in `FluxWeb.Plugs.IpAllowlist`; this context owns storage, validation,
  and the allow/deny decision (`ip_allowed?/2`), with a short-lived cache
  (`Flux.Security.Cache`) on the hot path.
  """

  import Ecto.Query, warn: false

  alias Flux.Repo
  alias Flux.Security.{Cache, SecuritySettings}

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
          changes: %{"ip_allowlist" => settings.ip_allowlist}
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
    case allowlist(org_id) do
      [] -> true
      cidrs -> Enum.any?(cidrs, &InetCidr.contains?(&1, ip))
    end
  end

  # Parsed CIDR tuples for the org, cached. Invalid stored entries are dropped
  # defensively (they cannot normally be saved — see the changeset validation).
  defp allowlist(org_id) do
    Cache.fetch(org_id, fn ->
      org_id
      |> get_settings()
      |> Map.fetch!(:ip_allowlist)
      |> Enum.flat_map(&parse_cidr/1)
    end)
  end

  defp parse_cidr(cidr) do
    [InetCidr.parse_cidr!(cidr)]
  rescue
    _ -> []
  end
end
