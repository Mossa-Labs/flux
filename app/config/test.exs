import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir,
  t_cost: 1,
  m_cost: 8

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :flux, Flux.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  database: "flux_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :flux, FluxWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "5z0gV4tsKHWFqnliEAp31KckgFttgdFxSMYzbVD2ksm4R9wVqK7bVfRfxKLUweEO",
  server: false

# In test we don't send emails
config :flux, Flux.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Queue adapter for tests (in-memory)
config :flux, Flux.Queue, type: "memory"

config :flux, Flux.License, provider: Flux.License.Providers.Community

config :flux, Flux.AI, provider: Flux.AI.Providers.Basic

# Oban test mode - jobs are not executed automatically
config :flux, Oban, testing: :manual

# API authentication for tests
config :flux, FluxWeb.Plugs.ApiAuth, api_key: "test-api-key"

# The Test adapter captures rather than sends; the sender just has to exist.
config :flux, :mail_from, name: "Flux", address: "flux@test.local"
