defmodule Flux.Branding do
  @moduledoc """
  White-label branding: what name, colour and imagery the UI wears (MOS-483).

  Resolution runs through `Flux.Branding.Registry` to the active provider.
  Community always reports stock Flux; the commercial edition reports per-org
  branding once `:white_label` is entitled.

  ## Entitlement is re-checked on every read

  Not once at boot. A license that lapses past its grace window drops to
  Community while the node keeps running, and a customer who stops paying for
  white-label should stop *seeing* white-label — not keep their logo until
  somebody restarts the node. The cost is one `has_feature?/1` call per render,
  which is a cached tier lookup.

  ## One organization per deployment, for pre-auth pages

  The sign-in page renders before there is a scope, so there is no organization
  to read branding from. `for_deployment/0` answers with the deployment's
  organization — in practice the only one, since a Pro/Enterprise install is
  operationally single-tenant and `Flux.Accounts.Scope` already falls back the
  same way.

  **This silently changes meaning if a second organization is ever created.**
  Sign-in pages would keep showing the first organization's branding while the
  second organization's owner sees their own everywhere else. Anything that
  makes multi-org real needs to revisit this.
  """

  alias Flux.Branding.{Registry, Theme}

  @feature :white_label

  @doc "The active provider module."
  @spec provider() :: module()
  def provider, do: Registry.active()

  @doc """
  Whether this deployment may customise branding at all.

  UI should gate on this; every write path re-checks it independently, because a
  hidden form is not an access control.
  """
  @spec entitled?() :: boolean()
  def entitled?, do: Flux.License.has_feature?(@feature)

  @doc """
  Resolved branding for an organization.

  Returns stock Flux when unentitled, when `org_id` is nil, or when the
  organization has set nothing.
  """
  @spec for_org(term() | nil) :: Theme.t()
  def for_org(org_id)
  def for_org(nil), do: Theme.default()

  def for_org(org_id) do
    if entitled?() do
      provider().theme(org_id)
    else
      Theme.default()
    end
  end

  @doc """
  Branding for a signed-out visitor — see the module note on the single-org
  assumption.
  """
  @spec for_deployment() :: Theme.t()
  def for_deployment do
    if entitled?() do
      provider().theme(provider().deployment_org_id())
    else
      Theme.default()
    end
  end

  @doc """
  Branding for a scope, falling back to the deployment's when there is no
  organization in it (anonymous, or a user not yet in an org).
  """
  @spec for_scope(term()) :: Theme.t()
  def for_scope(%{organization_id: org_id}) when not is_nil(org_id), do: for_org(org_id)
  def for_scope(_), do: for_deployment()

  @doc """
  The display name outbound mail should come from, or `nil` to leave the
  operator's configured name alone.

  Only a *customised* name is returned. The stock brand name is the uppercase
  wordmark (`FLUX`), which is right in the chrome and wrong in a `From:` header —
  an unbranded deployment would start shouting at its own users. So this reports
  nothing unless someone actually set a name.

  The **address** is never branded: relays reject senders they are not
  authorised for, so it has to stay whatever the operator configured. Only the
  display name changes.

  Resolved from the deployment's organization rather than the recipient's,
  because a notifier knows who it is emailing but not on whose behalf — see the
  module note on the single-organization assumption.
  """
  @spec mail_from_name() :: String.t() | nil
  def mail_from_name do
    name = for_deployment().brand_name

    if name != Theme.default().brand_name, do: name
  end

  @doc """
  Stores branding for an organization.

  `{:error, [{field, message}]}` on rejection — a keyword list rather than a
  changeset, because the schema lives behind the provider contract.
  """
  @spec put(term(), map()) :: {:ok, Theme.t()} | {:error, Flux.Branding.Provider.errors()}
  def put(org_id, attrs) do
    with :ok <- require_entitlement() do
      provider().put(org_id, attrs)
    end
  end

  @doc "Validates and stores an uploaded image."
  @spec put_asset(term(), Flux.Branding.Provider.asset_kind(), binary()) ::
          {:ok, Theme.t()} | {:error, Flux.Branding.Provider.errors()}
  def put_asset(org_id, kind, bytes) when kind in [:logo, :favicon] and is_binary(bytes) do
    with :ok <- require_entitlement() do
      provider().put_asset(org_id, kind, bytes)
    end
  end

  @doc """
  Stored bytes for an asset, as `{:ok, binary, content_type, digest}` or `:none`.

  The content type is the provider's verdict on the bytes, not anything a client
  supplied — callers may serve it directly.
  """
  @spec asset(term(), Flux.Branding.Provider.asset_kind()) ::
          {:ok, binary(), String.t(), String.t()} | :none
  def asset(org_id, kind) when kind in [:logo, :favicon] do
    if entitled?() and function_exported?(provider(), :asset, 2) do
      provider().asset(org_id, kind)
    else
      :none
    end
  end

  defp require_entitlement do
    if entitled?() do
      :ok
    else
      {:error, [{:base, "White-label branding requires Flux Enterprise."}]}
    end
  end
end
