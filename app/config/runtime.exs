import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/flux start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :flux, FluxWeb.Endpoint, server: true
end

config :flux, FluxWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :flux, Flux.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Optional dedicated key for field-level secret encryption (MOS-587). When
  # unset, Flux.Vault derives its key from :secret_key_base above.
  if vault_key = System.get_env("FLUX_VAULT_KEY") do
    config :flux, Flux.Vault, key: vault_key
  end

  # Trusted reverse-proxy CIDRs (MOS-588), comma-separated, e.g.
  # FLUX_TRUSTED_PROXIES="10.0.0.0/8,172.16.0.0/12". Only when the immediate
  # peer is one of these is X-Forwarded-For trusted for the real client IP.
  if trusted = System.get_env("FLUX_TRUSTED_PROXIES") do
    proxies = trusted |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    config :flux, FluxWeb.Plugs.ClientIp, proxies: proxies
  end

  host = System.get_env("PHX_HOST") || "example.com"

  config :flux, FluxWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :flux, FluxWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :flux, FluxWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Mailer
  #
  # Configured entirely from the environment, so the same build serves an
  # operator running Flux on their own hardware with their own SMTP server and a
  # hosted deployment where we supply one. Nothing here branches on which.
  #
  # Set FLUX_SMTP_HOST to send mail. Without it the base config's
  # `Swoosh.Adapters.Local` stays in place — which stores mail in memory and
  # delivers nothing. That is the right default for dev, where the /dev/mailbox
  # preview shows it, and a trap in production, where that route is not even
  # mounted. So an unconfigured production node says so at boot rather than
  # swallowing sign-in emails in silence; see `Flux.Mailer.warn_if_unconfigured/0`.
  if smtp_host = System.get_env("FLUX_SMTP_HOST") do
    config :flux, Flux.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_host,
      port: String.to_integer(System.get_env("FLUX_SMTP_PORT") || "587"),
      username: System.get_env("FLUX_SMTP_USERNAME"),
      password: System.get_env("FLUX_SMTP_PASSWORD"),
      # `:always` upgrades the connection with STARTTLS and fails if the server
      # will not — the default (`:if_available`) silently sends credentials in
      # the clear against a server that does not offer it. Overridable because
      # some internal relays genuinely have no TLS, but that has to be chosen.
      tls: String.to_atom(System.get_env("FLUX_SMTP_TLS") || "always"),
      auth: if(System.get_env("FLUX_SMTP_USERNAME"), do: :always, else: :never),
      # Certificate verification comes from the OS trust store rather than being
      # disabled, which is the usual shortcut here.
      tls_options: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(smtp_host),
        depth: 3
      ],
      retries: 2,
      no_mx_lookups: false
  end

  # Only needed by API-based adapters (Mailgun, SES, Postmark…). Harmless for
  # SMTP, and set here so swapping in such an adapter does not also require
  # discovering that this line is missing.
  config :swoosh, :api_client, Swoosh.ApiClient.Req

  # Who mail comes from. Most SMTP relays reject or spam-file a sender they are
  # not authorised for, so this generally has to match the configured relay's
  # domain — which is exactly why it cannot be a compiled-in constant.
  #
  # Deliberately NOT under `Flux.Mailer`: Swoosh hands that entire keyword list
  # to the adapter, so extra keys would reach gen_smtp as unrecognised options.
  config :flux, :mail_from,
    name: System.get_env("FLUX_MAIL_FROM_NAME"),
    address: System.get_env("FLUX_MAIL_FROM_ADDRESS")

  # Queue adapter for production. Community defaults to the in-memory queue; the
  # "rabbitmq" type resolves to an upgrade-prompt stub unless the commercial
  # edition registers the real RabbitMQ adapter at boot.
  config :flux, Flux.Queue, type: System.get_env("FLUX_QUEUE_TYPE") || "memory"

  config :flux, Flux.License, provider: Flux.License.Providers.Community

  config :flux, Flux.AI, provider: Flux.AI.Providers.Basic

  # API authentication for production
  api_key =
    System.get_env("FLUX_API_KEY") ||
      raise """
      environment variable FLUX_API_KEY is missing.
      Generate a secure key for API authentication.
      """

  config :flux, FluxWeb.Plugs.ApiAuth, api_key: api_key
end
