# Mast

A small self-hosted dashboard for tracking a fleet of Linux servers and the
Elixir releases running on them. Phoenix 1.8 / Elixir 1.19 / OTP 28.

The look is borrowed from [Beszel](https://beszel.dev/); the patch logic is
borrowed from Coolify. See [`docs/adr/`](docs/adr/README.md) for the why
behind the choices.

## What works today

| | |
|---|---|
| Register servers (name, host, ssh user, port) | v0.1 |
| Beszel-style dashboard at `/` with CPU / Memory / Disk / Agent columns | v0.1 |
| Per-row **Check** button to run an SSH probe on demand | v0.2 |
| Background heartbeat every 30 s (dev) / 60 s (prod) — host metrics via SSH | v0.2 |
| OS detection + package-manager mapping (apt for now; dnf/pacman/zypper/apk parsers will follow) | v0.2 |
| Weekly OS patch scan via Oban cron (`apt list --upgradable`) | v0.2 |
| Per-server detail page at `/servers/:id` | v0.3 |
| **Apply All Updates** + per-package Apply buttons with live shell streaming | v0.3 |
| Auto-rescan after a successful apply | v0.3 |

Validated end-to-end against a real Ubuntu 24.04 box: SSH probe → 30 s metrics
refresh, `apt list --upgradable` parse to 62 pending packages, line-by-line
stream of arbitrary remote commands.

## Running locally

Requires [mise](https://mise.jdx.dev) and Docker.

```sh
mise install          # installs Erlang 28 + Elixir 1.19
mise run db:start     # starts Postgres on localhost:7544
mise run setup        # mix deps.get + ecto.setup
mise run dev          # mix phx.server
```

Then open <http://localhost:4000>.

### SSH key setup

Mast talks to servers using Erlang's `:ssh` application via `SSHKit`. It does
not read `~/.ssh/config`. Instead, drop (or symlink) your SSH private keys
into `priv/ssh/` with standard names (`id_rsa`, `id_ed25519`):

```sh
mkdir -p priv/ssh
ln -s ~/.ssh/your-key.pem priv/ssh/id_rsa
chmod 600 priv/ssh/id_rsa
```

The directory is gitignored. A future ADR (and a `Mast.PrivateKey` schema)
will replace this with per-server keys stored in the DB.

### sudo

Mast assumes the configured SSH user is either `root` or has passwordless
`sudo` for `apt-get`. The workers prefix `sudo -n ` to apt commands unless
the user is `root`. If `sudo` requires a password, `apt-get update -qq`
will fail silently and the scan will produce no updates.

## Testing

```sh
mise run test
```

The test suite uses `Mast.SSH.Stub` and does not touch the network. 56 tests.

## Project layout

```
lib/mast/
  fleet.ex              # context: list/create/delete + record_metrics, record_scan
  fleet/server.ex       # Ecto schema
  hosts/metrics.ex      # parsers for top/free/df
  hosts/os.ex           # /etc/os-release → package manager
  patches/apt.ex        # apt parser + safe_package_name?
  ssh.ex                # behaviour: run/2 and run_stream/4
  ssh/sshkit.ex         # production impl (SSHKit + Erlang :ssh)
  ssh/stub.ex           # test impl (in-memory Agent)
  workers/ticker.ex     # GenServer heartbeat (sub-minute cron)
  workers/connection_check.ex   # liveness + metrics
  workers/patch_scan.ex         # apt list --upgradable, weekly
  workers/apply_updates.ex      # apt upgrade -y, streams output
lib/mast_web/
  live/dashboard_live.ex  # / — all systems
  live/server_live.ex     # /servers/:id — detail + run log
docs/adr/               # architecture decisions — start here
```

## Next milestones (rough)

- **v0.4** — per-server app registry. Distributed Erlang-based health for
  Elixir releases that share a cookie; HTTP `/healthz` fallback otherwise.
  See ADR 0004.
- **v0.5** — `Mast.PrivateKey` schema so we can store per-server keys with
  passphrases instead of relying on `priv/ssh/`.
- **v0.x** — other package managers (`dnf`, `pacman`, `zypper`, `apk`); the
  parser shape and worker plumbing are already manager-agnostic.

See [`docs/adr/`](docs/adr/README.md) for the decisions behind those choices.
