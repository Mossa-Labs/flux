defmodule Flux.Auth.SSO.Providers.Community do
  @moduledoc """
  Community single sign-on provider: SSO is never available and never enforced.

  Reads answer "nothing configured" so the sign-in page renders exactly as it
  does without SSO, and password login is always allowed. Writes refuse with an
  upgrade message rather than raising.
  """

  @behaviour Flux.Auth.SSO.Provider

  @enterprise_required {:error, [{:base, "Single sign-on requires Flux Enterprise."}]}

  @impl true
  def available?, do: false

  @impl true
  def discover(_email), do: :none

  @impl true
  def authn_request(_config_id, _params), do: {:error, :enterprise_required}

  @impl true
  def consume(_config_id, _params), do: {:error, :enterprise_required}

  @impl true
  def sp_metadata(_config_id, _params), do: :none

  @impl true
  def password_login_allowed?(_user), do: true

  @impl true
  def get_config(_organization_id), do: nil

  @impl true
  def put_config(_organization_id, _attrs, _opts), do: @enterprise_required

  @impl true
  def delete_config(_organization_id), do: @enterprise_required

  @impl true
  def set_enforcement(_organization_id, _enforce), do: @enterprise_required

  @impl true
  def add_domain(_organization_id, _domain), do: @enterprise_required

  @impl true
  def verify_domain(_organization_id, _domain_id), do: @enterprise_required

  @impl true
  def remove_domain(_organization_id, _domain_id), do: @enterprise_required

  @impl true
  def linked_users(_organization_id), do: %{}
end
