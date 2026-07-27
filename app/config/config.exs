# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Build identity (MOS-586). Git is unavailable at runtime and `.git` is excluded
# from the Docker build context, so the revision has to be injected at build time
# — the release pipeline passes these as Docker build args promoted to ENV.
# Absent (a laptop build) → "dev", which `Flux.BuildInfo` reports as unreleased so
# an unreproducible build is obvious rather than passing for a shipped one.
#
# Read here rather than in runtime.exs because `Flux.BuildInfo` resolves them with
# `Application.compile_env/3`: that tracks changes and forces a recompile, whereas
# a module attribute reading `System.get_env/1` would silently bake a stale SHA.
config :flux, :build_info,
  version: Mix.Project.config()[:version],
  core_sha: System.get_env("FLUX_CORE_SHA"),
  built_at: System.get_env("FLUX_BUILD_TIME")

config :flux, :scopes,
  accounts_user: [
    default: false,
    module: Flux.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Flux.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :flux, :scopes,
  user: [
    default: true,
    module: Flux.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Flux.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :flux,
  ecto_repos: [Flux.Repo],
  generators: [timestamp_type: :utc_datetime],
  # :org_centric
  rbac_mode: :team_centric

# Configure the endpoint
config :flux, FluxWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FluxWeb.ErrorHTML, json: FluxWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Flux.PubSub,
  live_view: [signing_salt: "cf5tkidT"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :flux, Flux.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  flux: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --external:/assets/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  flux_builder: [
    args:
      ~w(js/builder/index.tsx --bundle --target=es2022 --format=esm --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  flux: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban configuration (base settings shared across environments)
config :flux, Oban,
  repo: Flux.Repo,
  queues: [default: 10, polling: 5, webhooks: 20],
  plugins: [
    # Nightly at 03:00 UTC: prune audit entries past the retention window. The
    # worker calls `Flux.Audit.prune/1`, a no-op on Community (no audit store);
    # the Enterprise provider does the actual deletion (MOS-482).
    {Oban.Plugins.Cron, crontab: [{"0 3 * * *", Flux.Workers.AuditPruner}]}
  ]

# Audit-log retention window in days (Enterprise). Default 90d; deployments can
# raise it (1yr+). The pruner deletes entries older than this.
config :flux, Flux.Audit, retention_days: 90

# Pipeline supervision backend. The Community edition is single-node only.
# The Pro build (flux_pro) overrides this with the Horde-backed distributed
# backend to enable horizontal scaling / HA.
config :flux, Flux.Pipeline.Supervision, impl: Flux.Pipeline.Supervision.Local

# Abuse-protection safety valve (MOS-450), cross-tier / not license-gated:
# burst rate per API key.
config :flux, FluxWeb.Plugs.BurstLimiter, limit: 1_000, window_ms: 1_000

# Field-level encryption at rest for sink secrets (MOS-587). When `key` is nil
# the endpoint :secret_key_base is used, so encryption is on by default with no
# extra config. Set FLUX_VAULT_KEY (see runtime.exs) to use a dedicated key.
config :flux, Flux.Vault, key: nil

# Trusted reverse-proxy CIDRs for client-IP resolution (MOS-588). Empty by
# default: conn.remote_ip is the TCP peer and X-Forwarded-For is not trusted.
# Behind an L7 load balancer, set FLUX_TRUSTED_PROXIES (see runtime.exs).
config :flux, FluxWeb.Plugs.ClientIp, proxies: []

# Per-org + node-wide caps on user-initiated pipeline starts (MOS-450).
config :flux, Flux.Pipeline.Manager,
  start_limit: 20,
  start_node_limit: 100,
  start_window_ms: 60_000

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
