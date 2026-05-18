# Mast

A small self-hosted dashboard for tracking a personal fleet of Linux
servers and the Elixir releases running on them. Phoenix 1.8 / Elixir 1.19
/ OTP 28.

## Who this is for

People who run a handful of Linux boxes — usually Ubuntu, Debian or
Amazon Linux — that host their own Elixir/BEAM apps, and want one place
to see "are they up, do they need patches, are the apps healthy."

## Who this isn't for

If you need a full PaaS with git-push deploys, Docker app management, or
a polished generic agent-based fleet tool, you'll be happier with
[Coolify](https://coolify.io) or [Beszel](https://beszel.dev). Mast is
intentionally narrow:

- No host-side agent. SSH + the BEAM is enough (see ADR 0005).
- No deploy pipeline, no proxy management, no preview environments.
- App monitoring is **Elixir-first**. Distributed Erlang gives us better
  signal than HTTP probes, but you have to be running BEAM to get it
  (see ADR 0004). Plain HTTP fallback is planned, not a focus.

So: simple monitoring, security updates, and Elixir/BEAM-aware uptime.
If you don't fit that, the tools above are better.

## What works today

| | |
|---|---|
| Register servers with a name, host, ssh user, port | v0.1 |
| Beszel-style dashboard at `/` with CPU / Memory / Disk per box | v0.1 |
| Per-row **Check** button to run an SSH probe on demand | v0.2 |
| Background heartbeat every 30 s (dev) / 60 s (prod) | v0.2 |
| OS detection + package-manager mapping (apt today) | v0.2 |
| Weekly OS patch scan via Oban cron (`apt list --upgradable`) | v0.2 |
| Per-server detail page at `/servers/:id` | v0.3 |
| **Apply All Updates** + per-package Apply with live shell streaming | v0.3 |
| Auto-rescan after a successful apply | v0.3 |
| SSH private keys stored encrypted at rest, used per-server | v0.4 |
| Key dropdown in the Add System modal (selects from registered keys) | v0.4 |
| App monitoring: list running Elixir releases per host, refresh on demand | v0.4 |
| Fleet-wide `/apps` view and per-app detail page at `/apps/:id` | v0.4 |

Validated end-to-end against a real Ubuntu 24.04 box and an Amazon Linux
2023 box: SSH probe → metrics refresh, patch scan finding real packages,
`apt upgrade -y` streamed live, encrypted key round-tripped through the
DB and used to dial production.

## Running locally

Requires [mise](https://mise.jdx.dev) and Docker.

```sh
mise install          # Erlang 28 + Elixir 1.19
mise run db:start     # Postgres in docker on localhost:7544
mise run setup        # mix deps.get + ecto.setup
mise run dev          # mix phx.server
```

Then open <http://localhost:4000>.

### Adding your first SSH key

Mast does **not** read `~/.ssh/config`. Add a key through the (forthcoming)
key management UI or, until then, via IEx:

```elixir
{:ok, _} = Mast.Keys.create_key(%{
  name: "elpajo prod",
  body: File.read!("/path/to/your.pem")
})
```

The PEM is parsed, fingerprinted, and stored encrypted (AES-256-GCM via
Cloak). Then pick it from the dropdown when adding a server.

### Encryption key

`MAST_VAULT_KEY` is required in production. Generate one once and put it
in your secrets manager:

```sh
mix phx.gen.secret 32 | base64
```

Dev/test use committed fallback keys (these aren't secrets — the dev DB
has no real data).

### sudo

The configured SSH user must be `root` or have passwordless `sudo` for
`apt-get`. The workers prefix `sudo -n ` to apt commands; if sudo requires
a password, scans and applies will fail silently.

## Making your Elixir app monitorable

Mast monitors Elixir applications by invoking
`bin/<release> rpc <expression>` over the existing SSH connection. The
expression runs inside your release's BEAM, reads
`:application.which_applications/0`, and returns a JSON payload. One SSH
roundtrip per probe, no extra ports, no cookies for mast to manage. See
[ADR 0004](docs/adr/0004-elixir-native-monitoring.md) for the rationale.

For this to work, your mix release needs two things:

### 1. Short-name distribution

Mix release defaults to long-name distribution (`-name <release>@<host>`),
which expects `hostname -f` to return a fully qualified domain name. On
most cloud VMs (EC2, GCE, fly.io machines), `hostname -f` returns a short
name like `ip-172-31-15-23` and the BEAM refuses to form the node. That
breaks `bin/<release> rpc` and any tool that wants to attach.

Switch to short-name distribution by creating `rel/env.sh.eex` in your
project:

```sh
#!/bin/sh
export RELEASE_DISTRIBUTION=sname
export RELEASE_NODE=<your_app_name>
```

`mix release` picks this up automatically on the next build and ships it
inside the release. After deploying and restarting, `bin/<app> rpc` works
in under a second:

```sh
$ time /opt/myapp/current/bin/myapp rpc 'IO.inspect(:pong)'
:pong
real    0m0.31s
```

If your host already has a proper FQDN (`hostname -f` returns something
like `myhost.internal.example.com` that resolves back to the same IP),
you can keep long names. Short names are simpler and the default mix
release tooling assumes them.

### 2. Wire the release path into mast

On the server's detail page in mast, open the **Settings** tab and set
**Release command** to the absolute path of your release's
`bin/<app>` script, e.g. `/opt/hermes/current/bin/hermes`. Mast will
probe it every 30 seconds and surface results on the **Apps** tab and
the fleet-wide `/apps` page.

That's the whole integration — no agent to install, no metrics endpoint
to expose, no port to open beyond SSH.

## Testing

```sh
mise run test
```

The test suite uses `Mast.SSH.Stub` and does not touch the network.

## More

- [`docs/adr/`](docs/adr/README.md) — architecture decisions. Start here
  to understand why anything is the way it is.
- [`CLAUDE.md`](CLAUDE.md) — conventions and guardrails for AI agents
  (and humans).
- GitHub issues on this repo are the canonical task tracker for
  follow-up work.

## Roadmap

- **v0.5** — full key management UI (list, add via paste, delete)
- **v0.5** — richer per-app detail via `:observer_backend.*` over the
  same `rpc` channel (sup tree, scheduler load, memory categories)
- **Later** — dist-upgrade for kernel/held packages, dnf/pacman/zypper
  parsers, app-level alerting on status transitions, plain HTTP/TCP
  fallback for non-Elixir apps
