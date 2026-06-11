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
  """

  @behaviour Flux.Alerts.Provider

  @agent __MODULE__.Agent

  def reset(rules \\ []) do
    case Process.whereis(@agent) do
      nil -> Agent.start_link(fn -> %{rules: rules, seq: length(rules)} end, name: @agent)
      _ -> Agent.update(@agent, fn _ -> %{rules: rules, seq: length(rules)} end)
    end

    :ok
  end

  defp state, do: Agent.get(@agent, & &1)

  @impl true
  def list_rules(org_id), do: Enum.filter(state().rules, &(&1.organization_id == org_id))

  @impl true
  def get_rule(org_id, rule_id) do
    case Enum.find(
           state().rules,
           &(&1.organization_id == org_id and to_string(&1.id) == to_string(rule_id))
         ) do
      nil -> {:error, :not_found}
      rule -> {:ok, rule}
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
          channels: attrs["channels"] || [],
          enabled: Map.get(attrs, "enabled", true),
          cooldown_minutes: attrs["cooldown_minutes"] || 0,
          last_fired_at: nil,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }

        {rule, %{st | rules: st.rules ++ [rule], seq: id}}
      end)

    {:ok, rule}
  end

  @impl true
  def update_rule(org_id, rule_id, attrs) do
    update(org_id, rule_id, fn rule ->
      %{
        rule
        | name: attrs["name"] || rule.name,
          trigger_config: attrs["trigger_config"] || rule.trigger_config,
          channels: attrs["channels"] || rule.channels,
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
          {{:ok, rule}, %{st | rules: List.replace_at(st.rules, idx, rule)}}
      end
    end)
  end
end
