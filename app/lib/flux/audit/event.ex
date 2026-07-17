defmodule Flux.Audit.Event do
  @moduledoc """
  Canonical audit-event vocabulary and normalization (MOS-482).

  Single source of truth for the action names in the MOS-482 event catalog and
  the builder that turns loose call-site attrs into the normalized map every
  `Flux.Audit.Provider` consumes. Keeping this here (public, gated) means both
  the Community no-op and the Enterprise provider speak the same vocabulary.

  Call sites pass a map with at least `:action`, and either an `:actor`
  (a `Flux.Accounts.Scope`, `Flux.Accounts.User`, `{:api_key, key}`, or
  `:system`) or explicit `:actor_id`/`:actor_type`. `organization_id` is taken
  from the attrs or derived from a `Scope` actor.
  """

  # Canonical action catalog, grouped by the MOS-482 event table. Kept as a
  # flat list for membership checks; unknown actions are still accepted (logged
  # as-is) so a new call site never crashes on an un-catalogued action.
  @actions ~w(
    login logout failed_login magic_link_sent
    pipeline_created pipeline_updated pipeline_started pipeline_stopped
    pipeline_paused pipeline_rolled_back pipeline_deleted
    sink_created sink_updated sink_enabled sink_disabled sink_deleted
    member_invited member_updated member_role_changed member_removed
    member_disabled member_reenabled
    organization_created organization_updated organization_deleted
    team_created team_updated team_deleted
    team_member_added team_member_updated team_member_removed
    api_key_created api_key_revoked
    rbac_mode_changed sso_configured
    alert_rule_created alert_rule_updated alert_rule_deleted alert_fired
  )a

  @actor_types ~w(user system api_key)a

  @doc "All catalogued action atoms."
  @spec actions() :: [atom()]
  def actions, do: @actions

  @doc "True if `action` is in the canonical catalog."
  @spec known_action?(atom() | String.t()) :: boolean()
  def known_action?(action) when is_atom(action), do: action in @actions
  def known_action?(action) when is_binary(action), do: action in Enum.map(@actions, &to_string/1)

  @doc """
  Normalizes call-site attrs into the canonical event map stored by a provider.

  Accepts a map or keyword list. Resolves `:actor` into `actor_id`/`actor_type`
  and folds an API-key prefix into `:metadata`. Never raises on missing keys.
  """
  @spec normalize(map() | keyword()) :: map()
  def normalize(attrs) when is_list(attrs), do: normalize(Map.new(attrs))

  def normalize(attrs) when is_map(attrs) do
    {actor_id, actor_type, org_from_actor, actor_meta} = resolve_actor(Map.get(attrs, :actor))

    %{
      organization_id: Map.get(attrs, :organization_id) || org_from_actor,
      actor_id: Map.get(attrs, :actor_id, actor_id),
      actor_type: normalize_actor_type(Map.get(attrs, :actor_type, actor_type)),
      action: to_string(Map.fetch!(attrs, :action)),
      resource_type: normalize_string(Map.get(attrs, :resource_type)),
      resource_id: normalize_string(Map.get(attrs, :resource_id)),
      changes: stringify(Map.get(attrs, :changes) || %{}),
      metadata: Map.merge(actor_meta, stringify(Map.get(attrs, :metadata) || %{}))
    }
  end

  # ── actor resolution ──────────────────────────────────────────────────────

  defp resolve_actor(nil), do: {nil, :system, nil, %{}}
  defp resolve_actor(:system), do: {nil, :system, nil, %{}}

  defp resolve_actor({:api_key, key}) when is_map(key) do
    meta =
      case Map.get(key, :prefix) || Map.get(key, :key_prefix) do
        nil -> %{}
        prefix -> %{"api_key_prefix" => to_string(prefix)}
      end

    {Map.get(key, :id), :api_key, Map.get(key, :organization_id), meta}
  end

  defp resolve_actor(%_{} = actor) do
    # A Flux.Accounts.Scope carries user + organization_id; a bare User carries id.
    org = Map.get(actor, :organization_id)

    cond do
      Map.has_key?(actor, :user) and is_map(actor.user) ->
        {Map.get(actor.user, :id), :user, org, %{}}

      Map.has_key?(actor, :id) ->
        {actor.id, :user, org, %{}}

      true ->
        {nil, :system, org, %{}}
    end
  end

  defp resolve_actor(_), do: {nil, :system, nil, %{}}

  defp normalize_actor_type(type) when type in @actor_types, do: to_string(type)
  defp normalize_actor_type(type) when is_binary(type), do: type
  defp normalize_actor_type(_), do: "system"

  defp normalize_string(nil), do: nil
  defp normalize_string(v) when is_binary(v), do: v
  defp normalize_string(v), do: to_string(v)

  # JSONB columns store string-keyed maps; normalize atom keys up front so the
  # Community no-op and the Enterprise writer agree on shape.
  defp stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify(_), do: %{}
end
