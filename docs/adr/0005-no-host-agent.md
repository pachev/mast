# ADR 0005: No host-side agent

Status: Accepted
Date: 2026-05-18

## Context

Coolify ships "Sentinel" — a Go binary that runs on every server and pushes
metrics back. Beszel ships its own agent. The question is whether Mast needs
one.

## Decision

**No agent.** For our scale and workload (handful of Ubuntu boxes running
Elixir releases), an agent buys nothing the BEAM doesn't already provide.

### How we get the data instead

| Signal | Mechanism |
|---|---|
| Server reachable | `Mast.SSH.run(server, "echo ok")` returns `{:ok, "ok\n"}`. |
| OS identity | `cat /etc/os-release` parsed once on first successful check, cached on the server row. |
| CPU / RAM / disk | Periodic SSH: `top -bn1 \| head -3`, `free -m`, `df -h /`. ~50ms round trip. |
| App liveness | Distributed Erlang: `Node.connect/1` + `:rpc.call` for any release that shares an Erlang cookie with Mast. Falls back to `/healthz` HTTP probe or TCP ping (ADR 0004). |
| Patch availability | `LANG=C apt list --upgradable 2>/dev/null` weekly, parsed by `Mast.Patches.Apt`. |

### Why not Coolify's approach

- **Per-host binary = per-host update path.** We'd need to manage Sentinel
  versions across the fleet. SSH commands have no version drift.
- **Push model = open inbound port on Mast.** Pull model only needs outbound
  SSH from Mast, which most servers already allow.
- **Coolify uses Sentinel because Laravel's worker model can't cheaply hold
  long-lived SSH connections.** BEAM's concurrency makes 50 parallel polls
  trivial.

## When we'd reconsider

- **Sub-second metric granularity** — SSH polling is fine at 60s, awkward at 5s.
- **Long-term metric history (graphs)** — we'd need a time-series store and
  something pushing into it more frequently than `:checks` runs.
- **Fleet size past ~50 hosts** — SSH RTT × hosts adds up.

If/when that happens, the agent would be a tiny Elixir release
(`mast_agent`) that joins the cluster over disterl, not a separate binary.
Reusing the BEAM means no new language, no new protocol.

## Consequences

- Mast holds an SSH connection (via SSHKit) per registered server while
  workers run. Connections are process-local and torn down with the worker.
- Host-level metrics lag by up to one minute. Acceptable for a home/personal
  fleet.
- We intentionally cannot report container-level metrics the way Sentinel
  does. Out of scope for v0.x.
