# ADR 0002: Phoenix/Elixir instead of running Coolify

Status: Accepted
Date: 2026-05-18

## Context

Coolify (Laravel/PHP) is the closest off-the-shelf option and we studied its
fleet-management slice closely (see `coolify-explained.html` in the parent
workspace). The patch-scan logic is ~600 lines of shell-parsing wrapped in
Laravel jobs. The remaining ~95% of Coolify is a Docker app platform we do not
need.

## Decision

Write our own in Phoenix 1.8 / Elixir 1.19 / OTP 28. Target apps are Elixir, so
the operator stack matches the workload stack. Reuse Coolify's *ideas* (regex,
parser shape, backoff strategy, package-name whitelist) without dragging in
PHP/Horizon/Redis.

## Alternatives considered

| Option | Why not |
|---|---|
| Run Coolify as-is | 700+ files, Postgres+Redis+Soketi, more than we need. |
| Fork Coolify, strip it | More effort to delete code safely than to rewrite the 600 lines. |
| Beszel | Closest to the look we want, but agent-required, written in Go, and lacks Elixir-aware monitoring. |
| Ansible/Salt | Pull model, no UI, no per-server liveness. |

## Consequences

- We give up the Coolify community / ecosystem.
- We get to use distributed Erlang and `:telemetry` directly for app
  monitoring — cheaper and more accurate than HTTP probes (ADR 0004).
- We must do our own auth (deferred until anyone else uses this).
