import Config

config :ehs_enforcement, Oban,
  testing: :manual,
  # Disable all plugins including Cron in test environment
  plugins: []

# Set the environment
config :ehs_enforcement, :environment, :test

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
#
# Pool sizing for test environment:
# - max_cases: 4 (concurrent test files)
# - avg connections per test file: 4-8 (heavy LiveView + DB operations)
# - total needed: 4 * 8 = 32 connections
# - formula: System.schedulers_online() * 4 = 8 cores * 4 = 32
config :ehs_enforcement, EhsEnforcement.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5434,
  database: "ehs_enforcement_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  # Increased from * 2 to * 4 for concurrent test stability
  pool_size: System.schedulers_online() * 4,
  # Connection queue management for better reuse under load
  # Log warning if checkout takes > 5s
  queue_target: 5000,
  # Check queue every 1s
  queue_interval: 1000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ehs_enforcement, EhsEnforcementWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "qQwK7Em234fldhImb233J+SsBWx/chBaje2paAYNK5G9RkV111KRX0EBS/b1QUwf",
  server: false

# In test we don't send emails
config :ehs_enforcement, EhsEnforcement.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Configure JWT signing secret for AshAuthentication tokens
config :ehs_enforcement,
       :token_signing_secret,
       "test-jwt-signing-secret-for-authentication-tokens"
