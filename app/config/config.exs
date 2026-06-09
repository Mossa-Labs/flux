# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

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
  queues: [default: 10, polling: 5, webhooks: 20]

# Pipeline supervision backend. The Community edition is single-node only.
# The Pro build (flux_pro) overrides this with the Horde-backed distributed
# backend to enable horizontal scaling / HA.
config :flux, Flux.Pipeline.Supervision, impl: Flux.Pipeline.Supervision.Local

# Abuse-protection safety valve (MOS-450), cross-tier / not license-gated:
# burst rate per API key.
config :flux, FluxWeb.Plugs.BurstLimiter, limit: 1_000, window_ms: 1_000

# Per-org + node-wide caps on user-initiated pipeline starts (MOS-450).
config :flux, Flux.Pipeline.Manager,
  start_limit: 20,
  start_node_limit: 100,
  start_window_ms: 60_000

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
