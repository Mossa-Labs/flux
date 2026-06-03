defmodule Flux.RBAC do
  @moduledoc """
  Resolves the **effective** RBAC mode, accounting for both configuration and
  license entitlement.

  Organization-centric RBAC is a Pro/Enterprise feature (`:org_rbac`). Even
  when `config :flux, rbac_mode: :org_centric` is set, an unlicensed build is
  pinned to `:team_centric` so the org-centric code paths stay dark. Call
  `mode/0` everywhere instead of reading `:rbac_mode` directly so the two
  consumers (`Flux.Structure`, `FluxWeb.SystemSettingsLive`) never diverge.
  """

  @type mode :: :team_centric | :org_centric

  @doc "Returns the effective RBAC mode for the current license + config."
  @spec mode() :: mode()
  def mode do
    configured = Application.get_env(:flux, :rbac_mode, :team_centric)

    if configured == :org_centric and Flux.License.has_feature?(:org_rbac) do
      :org_centric
    else
      :team_centric
    end
  end

  @doc "Whether the effective RBAC mode is organization-centric."
  @spec org_centric?() :: boolean()
  def org_centric?, do: mode() == :org_centric
end
