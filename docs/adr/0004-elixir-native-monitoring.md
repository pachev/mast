# ADR 0004: Elixir-native app monitoring

Status: Accepted (revised)
Date: 2026-05-18

## Revision (2026-05-18, v0.4 implementation)

We initially planned to use distributed Erlang (`Node.connect/1` + `:rpc`)
directly against monitored hosts. Two practical issues pushed us to a simpler
transport:

1. Disterl needs EPMD reachable plus a fixed `inet_dist_listen_min/max`
   range on the target. That's two open ports per host and a release
   configuration requirement.
2. Cookies need to be managed per host. Encrypting them at rest works,
   but the operational surface is wider than the value.

**Revised decision:** invoke `bin/<release> rpc <expression>` over the
existing SSH executor. Every mix release already supports `rpc`. The
expression runs inside the release's BEAM with the right cookie and
distribution settings; mast doesn't have to know either. One SSH command
per probe, no new ports, no new secrets.

The operator records a single `release_command` field on the server row
(e.g. `/opt/hermes/bin/hermes`) in the Settings tab. `Mast.Workers.AppProbe`
runs every 30s and stores the snapshot in the `applications` table.

For richer per-app data (sup tree, scheduler load, memory categories) we
will reuse the same `rpc` transport with `:observer_backend.*` calls,
which is the same data Observer's GUI displays.

## Original context

Coolify ships a Go agent ("Sentinel") on every host that pushes CPU/RAM/Docker
metrics. We don't want to run a separate binary on each box if we don't have to.

Our target workloads are Elixir releases, so we can talk to them at the BEAM
level.

## Decision (forward-looking)

When app-uptime monitoring is added, prefer in this order:

1. **Distributed Erlang.** If `mast` and the target release share an Erlang
   cookie, `Node.connect/1` plus `:rpc.call/4` gives instant liveness, scheduler
   utilisation, memory, process count, application state — no agent, no HTTP,
   no port to open beyond the EPMD/disterl ones already in use for clustering.
2. **PromEx / `:prometheus` scrape.** If the target apps already expose
   `/metrics`, scrape it on a 15-second tick with `Req`. Standard, language-
   agnostic, but requires opening the metrics port.
3. **Plain HTTP `/healthz`.** Cheapest fallback for apps that expose neither.
4. **TCP ping.** Last resort for non-Elixir apps. `:gen_tcp.connect/3` with a
   500 ms timeout.

For the *host itself* (CPU/RAM/disk), we will keep using SSH commands
(`top -bn1`, `free -m`, `df -h`) rather than an agent. They cost one SSH
roundtrip per poll, which is fine at fleet sizes under ~50.

## Why not just always use HTTP

HTTP `/healthz` says "process answered." Distributed Erlang says "BEAM is up,
scheduler not pinned, memory not pathological, GenServer X is alive, queue
length under Y." That's the difference between alerting at 03:00 and *knowing
why* at 03:00.

## Consequences

- For Elixir targets we'll need to manage cookies and reachable disterl ports.
- Network policy gets a little harder: distributed Erlang doesn't traverse most
  load balancers. Local datacenter / Tailscale / WireGuard only.
- Non-Elixir support is a strict downgrade, on purpose.
