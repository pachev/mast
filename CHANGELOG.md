# Changelog

All notable changes to Mast are tracked here. Format roughly follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [SemVer](https://semver.org/).

## [Unreleased]

### Added
- Observer-style per-app detail on AppLive: system snapshot
  (scheduler utilization, atom/port/process/ets counts, memory by
  category), collapsible supervision tree capped at depth 3, and
  top-10 processes by memory and message-queue length. Backed by
  `:observer_backend` over the existing `bin/<release> rpc` channel
  (issue #5).
- Graceful fallback when the target release omits `:runtime_tools`:
  the page keeps the scalar stats and surfaces an info banner
  pointing at the README instead of erroring.

### Changed
- AppLive: removed the "Memory over time" placeholder card. The real
  chart lands when application sampling exists (issue #15).
- README: documents the `extra_applications: [:runtime_tools]`
  requirement and the graceful-fallback behaviour.
- ADR 0004: records the `:observer_backend` probe expression and its
  view-scoped invocation (mount + Refresh, not the 30s worker).

## [0.5.0] - 2026-05-22

### Added
- Append-only audit log with a live view, cursor pagination, and
  server-side filters (ADR 0007).
- SSH key management tab in settings, with inline "add new key" support
  from the Add Server modal.
- Per-server Elixir app monitoring via `bin/<release> rpc`, including an
  app detail redesign with per-tab actions and a richer probe.
- `dnf` parser for AL2023 / Fedora-family patch scanning alongside the
  existing `apt` path.
- Optional `release_command` field on the Add Server modal.
- Paginated `ui_table` component for the Updates tab.
- JSON logs in production with worker metadata.
- Full component library (atoms, cards, navigation) and a sidebar shell
  driven by the Pencil design source.
- GitHub Actions workflow running `mix credo --strict`.
- `CONTEXT.md` glossary derived from the ADRs.

### Changed
- Server LiveView split into per-tab modules.
- UI components reorganized by family (buttons, feedback, containers,
  navigation, data, domain) and re-exported from a single entrypoint.
- ADR 0004 revised to document the SSH-exec probe transport.
- Server detail: load average, recent activity, audit pink rows, and
  progress bars on stat tiles.

### Removed
- Server removal flow moved out of the settings page.

### Docs
- ~500 LOC file size guardrail added to `CLAUDE.md`.
- UI design workflow rule documented; danger zone card added to the
  settings tab in the design source.

## [0.4.0] - prior

Baseline release before this changelog was kept. See `git log` for
details.
