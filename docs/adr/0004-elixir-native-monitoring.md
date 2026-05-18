# ADR 0004: Elixir-native app monitoring (eventually)

Status: Proposed — deferred to v0.4
Date: 2026-05-18

## Context

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
