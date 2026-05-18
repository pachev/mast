# Mast

A small self-hosted dashboard for tracking a fleet of Linux servers and the
Elixir releases running on them. Phoenix 1.8 / Elixir 1.19 / OTP 28.

The look is borrowed from [Beszel](https://beszel.dev/); the patch logic is
borrowed from Coolify (see ADRs).

## What's in v0.1

- Register servers (name, host, ssh user, port).
- Dashboard with CPU / Memory / Disk / Net / Agent columns and bar visualisations.
- `Mast.SSH` behaviour with a stubbed test impl and an SSHKit prod impl.
- `Mast.Patches.Apt` parser ported from Coolify, with package-name validation.
- No scheduler yet — metrics columns are placeholders until v0.2 wires up
  periodic checks.

## Running locally

Requires [mise](https://mise.jdx.dev) and Docker.

```sh
mise install          # installs Erlang 28 + Elixir 1.19
mise run db:start     # starts Postgres on localhost:7544
mise run setup        # mix deps.get + ecto.setup
mise run dev          # mix phx.server
```

Then open <http://localhost:4000>.

## Testing

```sh
mise run test
```

The test suite uses `Mast.SSH.Stub` and does not touch the network.

## Project layout

```
lib/mast/
  fleet.ex              # context (CRUD + status mutations)
  fleet/server.ex       # Ecto schema
  patches/apt.ex        # apt parser + safe_package_name?
  ssh.ex                # behaviour + dispatch
  ssh/sshkit.ex         # production impl (SSHKit + :ssh)
  ssh/stub.ex           # test impl (in-memory Agent)
lib/mast_web/
  live/dashboard_live.ex  # the whole UI
docs/adr/               # architecture decisions — read these first
```

## Next milestones (rough)

- v0.2 — periodic connection check + weekly patch scan via Oban.
- v0.3 — "apply updates" button with live-streamed shell output.
- v0.4 — per-server app registry; Elixir distribution-based health for
  releases that share a cookie; HTTP `/healthz` fallback otherwise.

See [`docs/adr/`](docs/adr/README.md) for the decisions behind those choices.
