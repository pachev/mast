import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :mast, Mast.Repo,
  username: "mast",
  password: "mast",
  hostname: "localhost",
  port: 7544,
  database: "mast_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :mast, :ssh, Mast.SSH.Stub
config :mast, :apps_probe, Mast.Apps.Probe.Stub

# Oban in :manual mode — no auto-cron, no async dispatch. Tests use
# Oban.Testing helpers (perform_job, assert_enqueued).
config :mast, Oban, testing: :manual

# No heartbeat in tests.
config :mast, :ticker_enabled, false

# Test-env Cloak key. Fixed so encrypted fixtures round-trip; not a secret.
config :mast, Mast.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1", key: Base.decode64!("xx0Y8t5sQYCSpHJWB+OSm9aXdSh5whlbk+lvSGTrXxg=")
    }
  ]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mast, MastWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "oE7xZFeJROd3f4dCM9h0nmWNXPIwSZ1xQuLhRKgNXCTvNDxUdP+J4GdtseMQAod4",
  server: false

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
