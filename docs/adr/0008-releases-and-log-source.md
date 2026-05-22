# ADR 0008: Releases as first-class, with per-Release Log Source

Status: Accepted
Date: 2026-05-22

## Context

CONTEXT.md has always said "a Server hosts zero or more Releases," but the
schema told a different story: `servers.release_command` is a single
column, so each Server has exactly zero or one Release in practice. Every
downstream module (`Mast.Apps.Probe.RpcExec`, `Mast.Workers.AppProbe`,
`MastWeb.AppLive`) inherited that assumption.

Issue #6 ("per-app log tail") exposed the gap. The natural place for log
config is on the thing whose logs you're tailing. With one Release per
Server, that's the Server. With two Releases on one Server (a web tier
and a worker tier sharing a box, which is normal in personal/team
fleets), it has to be the Release. Adding a `log_unit` column to
`servers` would entrench the 1:1 model right when we're about to outgrow
it.

Separately, the issue assumed systemd. That's correct for the canonical
BEAM deployment (mix release + systemd unit) but excludes anyone using
`logger_file_backend` or writing release logs to disk directly. We want
the abstraction to cover those without inviting Docker, Kubernetes, or
multi-stream complexity that Mast has explicitly said no to elsewhere
(ADR 0002, ADR 0005).

## Decision

### Releases become a table

```
releases
  - id              bigserial
  - server_id       bigint, not null, references servers(id) on delete cascade
  - name            string, nullable           # explicit handle; nil = derived
  - release_command string, nullable           # absolute path to bin/<release>; nil = no probe
  - log_source      string, not null, default "none"
                                               # "systemd" | "file" | "none"
  - log_target      string, nullable           # validated by adapter
  - inserted_at, updated_at
```

Uniqueness is enforced on the *effective* handle (`name` if set,
otherwise `Path.basename(release_command)`), scoped to `server_id`. If
two Releases on a Server would collide, the changeset rejects the second
and the Operator must set an explicit `name` on at least one.

`name` must match `^[a-z0-9][a-z0-9_-]*$` when set — URL-safe and
shell-safe, because the handle will appear in routes and (eventually) in
constructed commands.

### Single migration backfills and drops the old column

One migration:

1. Creates `releases` with the schema above.
2. For every Server with a non-empty `release_command`, inserts one
   Release row: `name = nil`, `release_command` copied, `log_source =
   "none"`. Emits one `release.created` Audit Event per backfilled row,
   actor `System`, with `metadata.backfilled_from = "servers.release_command"`.
3. Drops `release_command` from `servers`.

Rollback is not designed for. Mast is personal/team scale; a forward-only
migration is fine.

### Probes move to per-Release

`Mast.Workers.AppProbe` today takes a Server and probes the (single)
Release on it. After this ADR, the worker enqueues one job per Release
per Server *whose `release_command` is set*. `Mast.Apps.Probe.RpcExec.probe/1`
takes a `%Release{}`. A Release's probe failure marks *that Release*
unhealthy; the Server is still up iff its Check succeeds (unchanged from
the existing glossary).

`release_command` is **nullable** on `releases`. A Release with no
`release_command` is a valid configuration (logs-only); it simply isn't
probed. ReleaseLive Overview displays "probe not configured" for such
Releases. This decouples log streaming from probe-rpc — useful for
apps that don't expose `bin/<release>` (third-party services, shell
daemons whose logs you still want surfaced).

### Log Source is config on Release, not a noun

`log_source` is an enum (`:systemd | :file | :none`) and `log_target` is
the address inside that source. Two fields on the Release row, no
`log_sources` table, no `LogSource` schema. If a Release one day needs
two simultaneous streams (e.g. journalctl plus an audit file),
**that** is when Log Source graduates to its own entity. Today, single
stream per Release is enough.

`:docker` is deliberately omitted. Containerized BEAM releases break
`bin/release rpc` the same way they'd break `journalctl -u`, so
Docker isn't only a log story — it's a whole deployment shape that gets
its own ADR when someone needs it.

### Log Source Adapter behaviour

```elixir
defmodule Mast.Logs.Source do
  @callback stream_command(target :: String.t()) :: String.t()
  @callback validate_target(target :: String.t()) :: :ok | {:error, term}
end
```

Two implementations:

- `Mast.Logs.Systemd` — `stream_command/1` returns
  `"sudo -n journalctl -u <unit> -f -n 200 --output=cat"`. `validate_target/1`
  enforces `^[A-Za-z0-9@._-]+(\\.service)?$`.
- `Mast.Logs.File` — `stream_command/1` returns
  `"sudo -n tail -n 200 -F <path>"`. `validate_target/1` enforces
  absolute path, no shell metacharacters, no `..` segments, no globs.

The behaviour mirrors ADR 0003's `Executor`: small, two callbacks,
implementations plug in by name. Adapters know nothing about SSH; they
return a command string and validate input. `Mast.SSH.run_stream/4`
(unchanged) is what actually runs them.

### Always `sudo -n`

Both adapters prefix `sudo -n`. The README will gain a section
documenting the required NOPASSWD lines as a prerequisite for running
Mast, alongside the existing apt entries. Example:

```
mast ALL=(root) NOPASSWD: /usr/bin/journalctl -u *
mast ALL=(root) NOPASSWD: /usr/bin/tail -n 200 -F /var/log/myapp/*
```

`tail` rules are per-path to avoid wildcarding into a foot-gun. Failing
closed with a visible "sudo: a password is required" in the stream beats
silent permission errors.

### Lifecycle: LiveView-owned stream + Janitor

The Logs tab on `ReleaseLive` opens an SSH stream via
`Mast.SSH.run_stream/4` in `mount/3` (or when the tab is first
selected). The pid lives in `socket.assigns`. `terminate/2` stops it.
The LiveView keeps a ring buffer of the most recent 1000 lines in
assigns — drop-oldest on append. Reconnects start from the live tail
with no history; that's acceptable for v1.

For the cases `terminate/2` doesn't cover cleanly (LiveView crash,
Phoenix node restart mid-stream, remote `journalctl -f` lingering after
an SSH channel close), a `Mast.Logs.Janitor` GenServer in the
supervision tree:

- Registers `{liveview_pid, stream_ref}` when a stream opens.
- Monitors the LiveView pid.
- On `:DOWN`, force-closes the SSH channel for that stream ref.

The Janitor holds one ETS table and one `handle_info(:DOWN, ...)`
clause. It is not a per-Release server, not a buffer, not a PubSub
broker. Its only job is to catch the leaks that `terminate/2` misses.

### UI

```
/servers/:id                              ServerLive
  ├── Overview
  ├── Patches
  ├── Audit
  └── Releases                            # was: Apps
        list + add/remove, dropdown links to:

/servers/:id/releases/:name               ReleaseLive  # was: AppLive
  ├── Overview     # probe detail + deps (today's AppLive content)
  ├── Logs         # new — streams via Log Source
  └── Settings     # name, release_command, log_source, log_target
```

`MastWeb.AppLive` renames to `MastWeb.ReleaseLive`, file split
unchanged (`release_live/view.ex`). Release-level config moves off
`ServerLive`'s Settings tab onto `ReleaseLive`'s Settings tab. Server's
Settings tab keeps Server-only fields (name, host, user, port,
private_key).

`:name` in the URL is the effective handle (explicit `name` or derived
basename), URL-safe by validation.

### Audit Events

| event_type | site |
|---|---|
| `release.created` | `Mast.Fleet.create_release/1` (also: backfill migration, actor = System) |
| `release.deleted` | `Mast.Fleet.delete_release/1` |
| `release.updated` | `Mast.Fleet.update_release/2` (any change to name / release_command / log_source / log_target) |

Probes and log-stream opens are **not** audited. Both are read-only,
high-frequency, Operator-initiated reads with no state change on the
Server. Mirrors how Checks and Probes are already treated.

## Consequences

- `Mast.Apps.Probe.RpcExec` and `Mast.Workers.AppProbe` take a Release,
  not a Server. The dashboard's "apps per server" rollup becomes a
  count + status aggregate over the Server's Releases.
- `MastWeb.AppLive` rename is mechanical but touches routes, templates,
  tests, and any references in CLAUDE.md.
- The backfill migration emits Audit Events from within the migration.
  This is the first migration to do so; the pattern is one `Repo.insert_all`
  for `releases`, one `Repo.insert_all` for `audit_events`, both inside
  the same migration's `change/0`.
- Log streams are best-effort. SSH drop or remote process death surfaces
  as an end-of-stream event in the LiveView; the Operator can re-open
  the tab to reconnect. No automatic retry in v1.
- `:file` log sources cannot use globs. Operators tailing multi-file
  apps must pick one file (typically the current one — `tail -F` follows
  rotation). Worth revisiting when someone files an issue.

## What we explicitly did NOT decide here

- **Multi-stream Releases.** If a Release ever needs two live streams,
  Log Source graduates to a `log_sources` table. Until then, one
  `(log_source, log_target)` pair per Release.
- **Docker / Kubernetes Releases.** Out of scope; gets its own ADR.
- **Cross-reconnect history.** Reconnecting the Logs tab starts from
  the live tail. A supervised per-Release GenServer with a ring buffer
  could preserve history across reconnects (and de-duplicate streams
  across multiple viewers). Deferred — see the lifecycle section.
- **Search / filter / download.** Tail only. Search is its own scope.
  Download-all is a plausible v2 feature.
- **Retention or rate limits on `release.updated` events.** If
  config-churn becomes noisy in audit, ADR 0007's prune job inherits
  the problem.
