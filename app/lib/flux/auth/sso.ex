defmodule Flux.Auth.SSO do
  @moduledoc """
  Single sign-on: the facade every caller goes through.

  Resolution runs through `Flux.Auth.SSO.Registry` to the active
  `Flux.Auth.SSO.Provider`. Community resolves to a stub under which SSO is
  never available and never enforced; a real provider is supplied at runtime
  once `:sso` is entitled.

  ## Entitlement is re-checked on every call

  Not once at boot. When a license lapses the node keeps running on Community
  terms, and from that moment single sign-on is hidden *and no longer enforced*:
  password and magic-link sign-in work again for everyone. That is deliberate.
  A stale "require SSO" flag must never lock an organization out of its own
  data, and members provisioned through SSO have no password, so the magic link
  is how they get back in.

  ## Adoption

  Organizations usually turn SSO on long after they started with passwords, so
  nothing here assumes a fresh organization. Configuring SSO changes nothing for
  existing members. Their accounts link on their first SSO sign-in, and
  `linked_users/1` shows who has done so. Only when an owner turns on
  enforcement do password sessions end, and passwords are kept so turning it off
  again restores access.
  """

  import Ecto.Query

  alias Flux.Accounts
  alias Flux.Accounts.{Scope, User}
  alias Flux.Auth.SSO.{Config, Domain, Registry}
  alias Flux.Repo
  alias Flux.Structure.{Organization, OrganizationMember, Team, TeamMember}

  @feature :sso
  @not_entitled {:error, [{:base, "Single sign-on requires Flux Enterprise."}]}

  @doc "The active provider module."
  @spec provider() :: module()
  def provider, do: Registry.active()

  @doc """
  Whether this deployment may use single sign-on at all.

  UI gates on this; every write re-checks it independently, because a hidden
  form is not an access control.
  """
  @spec entitled?() :: boolean()
  def entitled?, do: Flux.License.has_feature?(@feature)

  @doc "Whether the sign-in page should offer single sign-on."
  @spec available?() :: boolean()
  def available?, do: entitled?() and provider().available?()

  @doc "The configuration that owns `email`'s domain, if that domain is verified."
  @spec discover(String.t()) :: {:ok, String.t()} | :none
  def discover(email) when is_binary(email) do
    if entitled?(), do: provider().discover(String.trim(email)), else: :none
  end

  def discover(_), do: :none

  @doc "The identity-provider URL that starts a sign-in."
  @spec authn_request(String.t(), Flux.Auth.SSO.Provider.authn_params()) ::
          {:ok, String.t()} | {:error, term()}
  def authn_request(config_id, params) do
    if entitled?(),
      do: provider().authn_request(config_id, params),
      else: {:error, :enterprise_required}
  end

  @doc "Validates an identity-provider response and resolves it to a user."
  @spec consume(String.t(), Flux.Auth.SSO.Provider.consume_params()) ::
          {:ok, User.t()} | {:error, term()}
  def consume(config_id, params) do
    if entitled?(),
      do: provider().consume(config_id, params),
      else: {:error, :enterprise_required}
  end

  @doc "Service-provider metadata XML."
  @spec sp_metadata(String.t(), %{acs_url: String.t()}) :: {:ok, String.t()} | :none
  def sp_metadata(config_id, params) do
    if entitled?(), do: provider().sp_metadata(config_id, params), else: :none
  end

  @doc """
  Whether `user` may sign in with a password or a magic link.

  Always `true` when SSO is not entitled. Otherwise `false` when an organization
  the user belongs to, and does not own, requires single sign-on.
  """
  @spec password_login_allowed?(User.t()) :: boolean()
  def password_login_allowed?(%User{} = user) do
    not entitled?() or provider().password_login_allowed?(user)
  end

  @doc "The organization's configuration, or `nil` (always `nil` when unentitled)."
  @spec get_config(term() | nil) :: Config.t() | nil
  def get_config(nil), do: nil

  def get_config(organization_id) do
    if entitled?(), do: provider().get_config(organization_id)
  end

  @doc """
  Creates or updates the scope's organization configuration.

  `base_url` is the deployment's current public URL. A new configuration takes
  its entity ID from it.
  """
  @spec put_config(Scope.t(), map(), String.t()) ::
          {:ok, Config.t()} | {:error, Flux.Auth.SSO.Provider.errors()}
  def put_config(%Scope{organization_id: org_id} = scope, attrs, base_url) do
    with :ok <- require_entitlement(),
         {:ok, config} <- provider().put_config(org_id, attrs, base_url: base_url) do
      audit(scope, :sso_configured, config, %{"idp_entity_id" => config.idp_entity_id})
      {:ok, config}
    end
  end

  @doc "Removes the scope's organization configuration, its domains and linked identities."
  @spec delete_config(Scope.t()) :: :ok | {:error, Flux.Auth.SSO.Provider.errors()}
  def delete_config(%Scope{organization_id: org_id} = scope) do
    with :ok <- require_entitlement(),
         :ok <- provider().delete_config(org_id) do
      audit(scope, :sso_config_deleted, nil, %{})
      :ok
    end
  end

  @doc """
  Turns enforcement on or off for the scope's organization.

  Turning it **on** ends every existing web session of the organization's
  members, except owners. Those sessions were established under rules that no
  longer apply, and leaving them running would make "require SSO" mean "require
  SSO from next month". The revoked session tokens are returned so the caller
  can disconnect their live sockets. Passwords and API keys are left alone.
  """
  @spec set_enforcement(Scope.t(), boolean()) ::
          {:ok, Config.t(), [Accounts.UserToken.t()]}
          | {:error, Flux.Auth.SSO.Provider.errors()}
  def set_enforcement(%Scope{organization_id: org_id} = scope, enforce)
      when is_boolean(enforce) do
    with :ok <- require_entitlement(),
         {:ok, config} <- provider().set_enforcement(org_id, enforce) do
      audit(scope, :sso_enforcement_changed, config, %{"enforce_sso" => enforce})

      revoked =
        if enforce do
          tokens = org_id |> non_owner_member_ids() |> Accounts.delete_session_tokens_for_users()

          audit(scope, :sso_sessions_revoked, config, %{
            "sessions" => length(tokens),
            "users" => tokens |> Enum.map(& &1.user_id) |> Enum.uniq() |> length()
          })

          tokens
        else
          []
        end

      {:ok, config, revoked}
    end
  end

  @doc "Claims `domain` for the scope's organization, pending DNS verification."
  @spec add_domain(Scope.t(), String.t()) ::
          {:ok, Domain.t()} | {:error, Flux.Auth.SSO.Provider.errors()}
  def add_domain(%Scope{organization_id: org_id} = scope, domain) when is_binary(domain) do
    with :ok <- require_entitlement(),
         {:ok, %Domain{} = d} <- provider().add_domain(org_id, domain) do
      audit(scope, :sso_domain_added, nil, %{"domain" => d.domain})
      {:ok, d}
    end
  end

  @doc "Checks a claimed domain's TXT record and marks it verified."
  @spec verify_domain(Scope.t(), term()) ::
          {:ok, Domain.t()} | {:error, Flux.Auth.SSO.Provider.errors()}
  def verify_domain(%Scope{organization_id: org_id} = scope, domain_id) do
    with :ok <- require_entitlement(),
         {:ok, %Domain{} = d} <- provider().verify_domain(org_id, domain_id) do
      audit(scope, :sso_domain_verified, nil, %{"domain" => d.domain})
      {:ok, d}
    end
  end

  @doc "Drops a domain claim."
  @spec remove_domain(Scope.t(), term()) :: :ok | {:error, Flux.Auth.SSO.Provider.errors()}
  def remove_domain(%Scope{organization_id: org_id} = scope, domain_id) do
    with :ok <- require_entitlement(),
         :ok <- provider().remove_domain(org_id, domain_id) do
      audit(scope, :sso_domain_removed, nil, %{"domain_id" => to_string(domain_id)})
      :ok
    end
  end

  @doc """
  Users of the organization who have signed in with SSO, mapped to their last
  SSO sign-in. Empty when unentitled.
  """
  @spec linked_users(term() | nil) :: %{optional(term()) => DateTime.t() | nil}
  def linked_users(nil), do: %{}

  def linked_users(organization_id) do
    if entitled?(), do: provider().linked_users(organization_id), else: %{}
  end

  # Everyone with a membership in the organization, by org role or through one of
  # its teams, minus its owners. Disabled members are included: their sessions
  # are already refused at the next request, and deleting the tokens costs
  # nothing.
  defp non_owner_member_ids(org_id) do
    owner_ids =
      from(o in Organization, where: o.id == ^org_id, select: o.user_id)
      |> union(
        ^from(m in OrganizationMember,
          where: m.organization_id == ^org_id and m.role == "owner",
          select: m.user_id
        )
      )
      |> Repo.all()

    member_ids =
      from(m in OrganizationMember, where: m.organization_id == ^org_id, select: m.user_id)
      |> union(
        ^from(tm in TeamMember,
          join: t in Team,
          on: t.id == tm.team_id,
          where: t.organization_id == ^org_id,
          select: tm.user_id
        )
      )
      |> Repo.all()

    member_ids
    |> MapSet.new()
    |> MapSet.difference(MapSet.new(owner_ids))
    |> MapSet.to_list()
  end

  defp require_entitlement do
    if entitled?(), do: :ok, else: @not_entitled
  end

  defp audit(scope, action, config, metadata) do
    Flux.Audit.log(%{
      actor: scope,
      organization_id: scope.organization_id,
      action: action,
      resource_type: :sso_config,
      resource_id: config && config.id,
      metadata: metadata
    })
  end
end
