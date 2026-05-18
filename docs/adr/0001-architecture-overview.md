# ADR 0001: Architecture Overview

Status: Accepted
Date: 2026-05-18

## Context

Need a small self-hosted dashboard to track a handful of Ubuntu servers and the
Elixir releases running on them. Existing tools (Coolify, Beszel, Komodo) either
do too much (full PaaS) or require an agent on every host.

For v0.1 the scope is intentionally narrow: list servers, see liveness, see OS
patches available, apply patches. App-uptime monitoring comes later and will be
Elixir-native (distributed Erlang) before falling back to HTTP/TCP probes.

## Decision

Build a Phoenix 1.8 LiveView app, single-node, Postgres-backed.

```
┌──────────────────────────────────────────────────────────┐
│ Browser  →  LiveView  →  Mast.Fleet (context)            │
│                       ↘                                  │
│                        Mast.SSH (behaviour)              │
│                          ├ SSHKit impl (prod)            │
│                          └ Stub impl   (test)            │
│                                                          │
│ Postgres ← Ecto ← Mast.Fleet.Server schema               │
└──────────────────────────────────────────────────────────┘
```

Layering:

- **Schema/Context layer (`Mast.Fleet`)** owns persistence and validation.
- **Executor layer (`Mast.SSH`)** is a behaviour with a swappable impl. Tests
  use a stub; production uses SSHKit on top of Erlang's `:ssh`.
- **Web layer (`MastWeb`)** is LiveView only. No JSON API yet — add later if
  needed.

## Consequences

- Single OTP application, single release. No Oban/Redis until a scheduler is
  actually needed (deferred to v0.3 — see ADR 0005 when written).
- Pure-function parsers and a behaviour-backed executor mean the bulk of the
  domain is testable without spinning up SSH.
- The app is small enough to read top-to-bottom in an evening.
