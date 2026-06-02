defmodule Flux.License do
  @moduledoc """
  Facade over the configured `Flux.License.Provider`.

  The provider module is configured via `config :flux, Flux.License,
  provider: Flux.License.Providers.Community`. EE builds switch to the
  EE provider via the commercial edition's runtime config.

  ## Pro/EE feature atoms

  Use these atoms for consistent entitlement checks across the codebase:

    * `:s3_sink` - S3/object storage sink
    * `:rabbit_mq_queue` - RabbitMQ queue backend
    * `:kafka_queue` - Kafka queue backend
    * `:advanced_ai` - Advanced AI detector/scorer
    * `:sso` - Single sign-on / SAML / OIDC
    * `:audit_log` - Audit logging
    * `:white_label` - White-label branding
    * `:mfa` - Multi-factor authentication
  """

  @spec provider() :: module()
  def provider do
    case Application.get_env(:flux, __MODULE__) do
      nil ->
        raise "No license provider configured. Set config :flux, Flux.License, provider: Flux.License.Providers.Community"

      config ->
        Keyword.fetch!(config, :provider)
    end
  end

  @spec fetch() :: {:ok, Flux.License.Provider.license()} | {:error, term()}
  def fetch, do: provider().fetch()

  @spec entitled?(Flux.License.Provider.feature()) :: boolean()
  def entitled?(feature) when is_atom(feature), do: provider().entitled?(feature)

  @spec tier() :: Flux.License.Provider.tier()
  def tier, do: provider().tier()
end
