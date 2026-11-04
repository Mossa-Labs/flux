defmodule Flux.AlertsTestProvider do
  @moduledoc """
  In-memory `Flux.Alerts.Provider` for tests, standing in for the Postgres-backed
  provider that ships in the commercial edition. Rules/history are held in an
  Agent so CRUD round-trips work without a Pro schema.

  Install with `Flux.Alerts.Registry.set_active/1` and reset on exit:

      Flux.AlertsTestProvider.reset()
      Flux.Alerts.Registry.set_active(Flux.AlertsTestProvider)
      on_exit(fn -> Flux.Alerts.Registry.set_active(Flux.Alerts.Providers.Community) end)

  Tests using it MUST be `async: false` (the registry is a global ETS table).

  Like a real provider it keeps channel secrets server-side: every callback
  returns redacted channels, and `update_rule/3` keeps a stored secret the form
  left blank. Tests read the stored plaintext with `stored_rules/1` and the
  channels a test send delivered to with `tested_channels/0`.
  """

  @behaviour Flux.Alerts.Provider

  alias Flux.Alerts.ChannelSecrets

  @agent __MODULE__.Agent

  def reset(rules \\ []) do
    initial = fn -> %{rules: rules, seq: length(rules), tested: []} end

    case Process.whereis(@agent) do
      nil -> Agent.start_link(initial, name: @agent)
      _ -> Agent.update(@agent, fn _ -> initial.() end)
    end

    :ok
  end

  defp state, do: Agent.get(@agent, & &1)

  @doc "The org's rules as stored, with plaintext channel secrets."
  def stored_rules(org_id), do: Enum.filter(state().rules, &(&1.organization_id == org_id))

  @doc "The channels `test_rule/2` delivered to, in order, with plaintext secrets."
  def tested_channels, do: state().tested

  @impl true
  def list_rules(org_id), do: org_id |> stored_rules() |> Enum.map(&to_public/1)

  @impl true
  def get_rule(org_id, rule_id) do
    case find(org_id, rule_id) do
      nil -> {:error, :not_found}
      rule -> {:ok, to_public(rule)}
    end
  end

  @impl true
  def create_rule(org_id, attrs) do
    rule =
      Agent.get_and_update(@agent, fn st ->
        id = st.seq + 1

        rule = %{
          id: id,
          organization_id: org_id,
          name: attrs["name"],
          trigger_type: String.to_existing_atom(attrs["trigger_type"]),
          trigger_config: attrs["trigger_config"] || %{},
          channels: ChannelSecrets.merge_stored(attrs["channels"] || [], []),
          enabled: Map.get(attrs, "enabled", true),
          cooldown_minutes: attrs["cooldown_minutes"] || 0,
          last_fired_at: nil,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }

        {rule, %{st | rules: st.rules ++ [rule], seq: id}}
      end)

    {:ok, to_public(rule)}
  end

  @impl true
  def update_rule(org_id, rule_id, attrs) do
    update(org_id, rule_id, fn rule ->
      %{
        rule
        | name: attrs["name"] || rule.name,
          trigger_config: attrs["trigger_config"] || rule.trigger_config,
          channels: merge_channels(attrs["channels"], rule.channels),
          cooldown_minutes: attrs["cooldown_minutes"] || rule.cooldown_minutes
      }
    end)
  end

  @impl true
  def toggle_rule(org_id, rule_id, enabled) do
    update(org_id, rule_id, &%{&1 | enabled: enabled})
  end

  @impl true
  def delete_rule(org_id, rule_id) do
    Agent.update(@agent, fn st ->
      %{
        st
        | rules:
            Enum.reject(
              st.rules,
              &(&1.organization_id == org_id and to_string(&1.id) == to_string(rule_id))
            )
      }
    end)

    :ok
  end

  @impl true
  def list_history(_org_id, _opts), do: []

  @impl true
  def test_channel(_channel), do: :ok

  @impl true
  def test_rule(org_id, rule_id) do
    case find(org_id, rule_id) do
      nil ->
        {:error, :not_found}

      rule ->
        Agent.update(@agent, &%{&1 | tested: &1.tested ++ rule.channels})
        {:ok, %{sent: length(rule.channels), failed: 0}}
    end
  end

  @impl true
  def record_event(_org_id, _event), do: :ok

  defp find(org_id, rule_id) do
    Enum.find(
      state().rules,
      &(&1.organization_id == org_id and to_string(&1.id) == to_string(rule_id))
    )
  end

  defp merge_channels(nil, stored), do: stored
  defp merge_channels(submitted, stored), do: ChannelSecrets.merge_stored(submitted, stored)

  defp to_public(rule), do: %{rule | channels: ChannelSecrets.redact(rule.channels)}

  defp update(org_id, rule_id, fun) do
    Agent.get_and_update(@agent, fn st ->
      case Enum.find_index(
             st.rules,
             &(&1.organization_id == org_id and to_string(&1.id) == to_string(rule_id))
           ) do
        nil ->
          {{:error, :not_found}, st}

        idx ->
          rule = fun.(Enum.at(st.rules, idx))
          {{:ok, to_public(rule)}, %{st | rules: List.replace_at(st.rules, idx, rule)}}
      end
    end)
  end
end
