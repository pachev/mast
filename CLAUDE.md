# Mast — Claude Code Briefing

## What this project is

Mast is a small self-hosted dashboard for a personal/team fleet of Linux
servers running Elixir/BEAM apps. Scope is intentionally narrow:

1. See the fleet (CPU/RAM/disk per box) at a glance
2. Detect and apply Linux security patches (apt today)
3. Monitor uptime + health of Elixir releases running on those boxes (planned
   via Erlang distribution + telemetry, see ADR 0004)

Mast is **not** trying to be Coolify, Beszel, or Komodo. If a user wants a
generic agent-based fleet tool or a full PaaS, those are better choices.
This is for people who already speak BEAM and want monitoring that speaks
it back.

## Stack

- Phoenix 1.8, LiveView
- Elixir 1.19 / Erlang OTP 28
- Postgres via Ecto (port 7544 in dev, see `mise.toml`)
- Oban for periodic + on-demand jobs
- SSHKit on top of Erlang `:ssh` for remote execution
- Cloak for field-level encryption (SSH key bodies)
- daisyUI + Tailwind v4

Tools managed by [mise](https://mise.jdx.dev). All common commands are
`mise run <task>` — see `mise.toml`.

Do not propose new deps without flagging it first.

## TDD is the default

Red → Green → Refactor. Announce the phase before writing implementation:

- **RED**: failing test, run it, paste the failure
- **GREEN**: smallest change that turns it green
- **REFACTOR**: clean up, tests still green

When the test names a module/function that doesn't exist, the compile error
**is** the RED.

For UI-only changes (CSS class tweaks, layout) you can skip TDD, but say so.

## Architecture decisions

ADRs live in `docs/adr/` and are numbered sequentially. Read these before
making structural changes; they capture rationale that isn't in the code:

- 0001 — architecture overview
- 0002 — Phoenix over running Coolify
- 0003 — SSH executor as a behaviour
- 0004 — Elixir-native monitoring (proposed)
- 0005 — No host-side agent
- 0006 — SSH key storage with cloak encryption

When you make a meaningful structural decision, write the next ADR (copy the
shape of an existing one — Context / Decision / Consequences).

## Task tracking

**GitHub issues on `pachev/mast` are the canonical tracker for follow-ups.**

- Mid-conversation work: use the TaskCreate tool to track steps.
- Cross-session follow-ups ("we'll add this later"): `gh issue create`, not
  TODOs in code and not memory entries.

## Migrations

`mix ecto.gen.migration <name>` → edit → `mix ecto.migrate`. Never edit a
migration that has been committed; write a new one instead.

## Security-sensitive guardrails

- Private key bodies are encrypted at rest via `Mast.Vault` (cloak). The
  *only* place plaintext should re-enter memory is `Mast.SSH.SSHKit.run/2`
  via `Mast.Keys.material/1`. Never write decrypted PEMs to disk, never log
  them, never put them in Oban args.
- Package names accepted from operators (apply-one-package path) MUST be
  validated against `Mast.Patches.Apt.safe_package_name?/1` before being
  interpolated into a shell command.
- All parser-bound apt commands run with `LANG=C`.
- Workers prefix `sudo -n ` to apt commands when the SSH user isn't root.

## What "done" looks like

A change is done when:

1. Tests cover it, written first (TDD).
2. `mix test` passes cleanly.
3. `mix format` has been run.
4. If the change crosses an architectural line, the relevant ADR is updated
   or a new one is added.
5. Commit messages are conventional (`feat:`, `fix:`, `docs:`, `chore:`,
   `test:`) and describe **why**, not just **what**.

## House style

- No em-dashes in user-facing copy. Hyphens or rephrase.
- No emojis in code or copy unless explicitly requested.
- No verbose docstrings on small helpers. If the name explains it, that's
  the doc.
- Prefer the simpler standard library / Ecto API over a clever macro.
- Don't add a layer of indirection until the second caller appears.
