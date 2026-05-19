# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mast,
  ecto_repos: [Mast.Repo],
  generators: [timestamp_type: :utc_datetime]

# SSH executor (overridden in test). Used by Mast.SSH.run/2.
config :mast, :ssh, Mast.SSH.SSHKit

# Background job processor. Two queues, kept small.
#   :checks — periodic liveness/patch scans (1 per server)
#   :runs   — user-triggered "apply updates" jobs that stream output
config :mast, Oban,
  repo: Mast.Repo,
  queues: [checks: 5, runs: 2],
  plugins: [
    # ConnectionCheck fan-out is driven by Mast.Workers.Ticker (sub-minute).
    # PatchScan stays on cron — weekly is plenty.
    {Oban.Plugins.Cron,
     crontab: [
       {"0 0 * * 0", Mast.Workers.PatchScan, args: %{all: true}}
     ]}
  ]

# Configure the endpoint
config :mast, MastWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MastWeb.ErrorHTML, json: MastWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Mast.PubSub,
  live_view: [signing_salt: "vLL6nd1M"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  mast: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  mast: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :server_id, :private_key_id, :run_id, :job_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
