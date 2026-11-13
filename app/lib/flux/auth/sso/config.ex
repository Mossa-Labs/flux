defmodule Flux.Auth.SSO.Config do
  @moduledoc """
  An organization's single sign-on configuration, as the settings UI sees it.

  A plain struct rather than a schema: storage lives behind
  `Flux.Auth.SSO.Provider`, and this is only what crosses the contract.
  """

  @typedoc """
  * `:id` - the stable, URL-safe configuration ID used in SSO routes.
  * `:idp_*` - what was read from the identity provider's metadata.
  * `:idp_metadata` - the metadata as last submitted, so the form can redisplay it.
  * `:sp_entity_id` - fixed when the configuration was created.
  * `:base_url` - the deployment URL the configuration was created under. When
    it differs from the current one, the identity provider is probably still
    pointing at the old address.
  * `:attribute_mapping` - assertion attribute names for `"email"`,
    `"first_name"`, `"last_name"` and `"groups"`.
  * `:role_mapping` - `{group, role}` pairs, in the order they are evaluated.
  * `:default_role` - the role for new users no group maps.
  * `:default_team_id` - in team-centric RBAC, the team new users join.
  """
  @type t :: %__MODULE__{
          id: String.t() | nil,
          organization_id: term(),
          provider_type: String.t(),
          idp_entity_id: String.t() | nil,
          idp_sso_url: String.t() | nil,
          idp_cert_fingerprints: [String.t()],
          idp_metadata: String.t() | nil,
          sp_entity_id: String.t() | nil,
          base_url: String.t() | nil,
          attribute_mapping: %{optional(String.t()) => String.t()},
          role_mapping: [{String.t(), String.t()}],
          default_role: String.t(),
          default_team_id: term() | nil,
          enforce_sso: boolean(),
          domains: [Flux.Auth.SSO.Domain.t()],
          updated_at: DateTime.t() | nil
        }

  defstruct id: nil,
            organization_id: nil,
            provider_type: "saml",
            idp_entity_id: nil,
            idp_sso_url: nil,
            idp_cert_fingerprints: [],
            idp_metadata: nil,
            sp_entity_id: nil,
            base_url: nil,
            attribute_mapping: %{},
            role_mapping: [],
            default_role: "member",
            default_team_id: nil,
            enforce_sso: false,
            domains: [],
            updated_at: nil

  @doc "Whether at least one of the configuration's domains is verified."
  @spec verified_domain?(t()) :: boolean()
  def verified_domain?(%__MODULE__{domains: domains}),
    do: Enum.any?(domains, &Flux.Auth.SSO.Domain.verified?/1)
end
