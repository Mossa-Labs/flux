defmodule Flux.SSOTestProvider do
  @moduledoc """
  Test-only single sign-on provider for exercising the SSO seam here: routes,
  the browser hand-off, enforcement and the settings UI. A real provider is
  supplied at runtime once `:sso` is entitled.

  Behaviour is driven by `config :flux, :test_sso`, a map:

    * `:available` - `available?/0` (default `true`).
    * `:config_id` - what `discover/1` returns for any address at `@acme.test`
      (default `"cfg_test"`). Other addresses get `:none`.
    * `:consume` - the result of `consume/2`. A function receives the params.
    * `:sso_only` - user IDs that may not use passwords.
    * `:config` - what `get_config/1` returns.
    * `:linked` - what `linked_users/1` returns.
    * `:put_error` - when set, `put_config/3` fails with it.
    * `:test_pid` - receives `{:sso, callback, args}` for every call that writes.

  Swap it in with `Flux.Auth.SSO.Registry.set_active/1` and restore the Community
  provider afterwards (so the test must be `async: false`).
  """

  @behaviour Flux.Auth.SSO.Provider

  alias Flux.Auth.SSO.{Config, Domain}

  @impl true
  def available?, do: Map.get(config(), :available, true)

  @impl true
  def discover(email) do
    if String.ends_with?(email, "@acme.test"),
      do: {:ok, Map.get(config(), :config_id, "cfg_test")},
      else: :none
  end

  @impl true
  def authn_request(config_id, params) do
    notify(:authn_request, {config_id, params})

    {:ok,
     "https://idp.acme.test/sso?" <>
       URI.encode_query(%{"SAMLRequest" => params.request_id, "RelayState" => params.relay_state})}
  end

  @impl true
  def consume(config_id, params) do
    notify(:consume, {config_id, params})

    case Map.get(config(), :consume, {:error, :not_configured}) do
      fun when is_function(fun, 1) -> fun.(params)
      result -> result
    end
  end

  @impl true
  def sp_metadata("cfg_test", %{acs_url: acs}),
    do: {:ok, ~s(<EntityDescriptor><ACS Location="#{acs}"/></EntityDescriptor>)}

  def sp_metadata(_config_id, _params), do: :none

  @impl true
  def password_login_allowed?(user), do: user.id not in Map.get(config(), :sso_only, [])

  @impl true
  def get_config(_org_id), do: Map.get(config(), :config)

  @impl true
  def put_config(org_id, attrs, opts) do
    notify(:put_config, {org_id, attrs, opts})

    case Map.get(config(), :put_error) do
      nil ->
        cfg = %Config{
          id: "cfg_test",
          organization_id: org_id,
          idp_metadata: attrs["idp_metadata"],
          idp_entity_id: "https://idp.acme.test",
          sp_entity_id: Keyword.fetch!(opts, :base_url) <> "/sso/cfg_test/metadata",
          base_url: Keyword.fetch!(opts, :base_url),
          attribute_mapping: attrs["attribute_mapping"],
          role_mapping: attrs["role_mapping"],
          default_role: attrs["default_role"]
        }

        put(:config, cfg)
        {:ok, cfg}

      errors ->
        {:error, errors}
    end
  end

  @impl true
  def delete_config(org_id) do
    notify(:delete_config, org_id)
    put(:config, nil)
    :ok
  end

  @impl true
  def set_enforcement(org_id, enforce) do
    notify(:set_enforcement, {org_id, enforce})
    cfg = %{(Map.get(config(), :config) || %Config{id: "cfg_test"}) | enforce_sso: enforce}
    put(:config, cfg)
    {:ok, cfg}
  end

  @impl true
  def add_domain(org_id, domain) do
    notify(:add_domain, {org_id, domain})

    {:ok,
     %Domain{
       id: 1,
       domain: domain,
       txt_record_name: "_flux-sso." <> domain,
       txt_record_value: "flux-sso-verification=t"
     }}
  end

  @impl true
  def verify_domain(org_id, domain_id) do
    notify(:verify_domain, {org_id, domain_id})
    {:ok, %Domain{id: domain_id, domain: "acme.test", verified_at: DateTime.utc_now()}}
  end

  @impl true
  def remove_domain(org_id, domain_id) do
    notify(:remove_domain, {org_id, domain_id})
    :ok
  end

  @impl true
  def linked_users(_org_id), do: Map.get(config(), :linked, %{})

  defp config, do: Application.get_env(:flux, :test_sso, %{})

  defp put(key, value), do: Application.put_env(:flux, :test_sso, Map.put(config(), key, value))

  defp notify(callback, args) do
    if pid = Map.get(config(), :test_pid), do: send(pid, {:sso, callback, args})
  end
end
