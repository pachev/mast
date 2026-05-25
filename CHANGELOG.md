# Changelog

All notable changes to Mast are tracked here. Format roughly follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [SemVer](https://semver.org/).

## [Unreleased]

### Added
- **Projects** — a named grouping of Servers as an organizational lens
  over the Fleet. A Server belongs to at most one Project; Servers
  without a Project render as plain cards on the Fleet page (no
  "Unassigned" pseudo-group). Manage from **Settings → Projects** (list,
  inline create, rename, recolor, delete). Assign at server creation
  time via the Add Server modal (with inline "Add new project") or from
  a Server's settings tab. Server detail shows a color-tinted Project
  badge near the title.
- Audit events: `project.created`, `project.renamed`, `project.recolored`,
  `project.deleted`, `server.project_assigned`, `server.project_unassigned`.
  Deleting a Project cascade-unassigns its Servers (preserved with
  `project_id` nulled) and emits one event per affected Server in the
  same transaction.
- New UI helpers `ui_project_group_header` and `ui_project_badge`
  (`MastWeb.Components.UI.Domain`), with previews on `/dev/ui`.
- Patch-apply output now streams into a modal with run persistence and
  reattach. A reloaded page reattaches to an in-flight apply instead of
  orphaning it (the modal auto-opens only while a run is still running).
  New `patch_runs` table (one row per server, upsert) with
  `Mast.Patches.Run` / `Mast.Patches.Runs`; `ApplyUpdates` batches log
  writes (flush every 25 lines and on close); new `ui_run_log_modal`
  component plus a `RunLogAutoScroll` hook (ADR 0012). This is the
  inline Updates-tab surface promised when the server-level Logs tab was
  removed in 0.6.0.
- Dev-only component showcase at `/dev/ui` (`DevUiLive`): every `ui_*`
  component grouped by family with a viewport-width toggle (375 / 414 /
  768 / 1024 / 1440 / full). Compiled out in `:prod`.

### Changed
- Responsive sweep across the `ui_*` component suite, which was built
  desktop-first. The sidebar collapses to a daisyUI drawer plus hamburger
  below `lg`; `ui_table`, `ui_tabs`, `ui_page_header`, `ui_card`,
  `ui_modal`, `ui_kv_table`, `ui_release_card`, `ui_audit_row`,
  `ui_card_title`, and `ui_chart_card` all gained breakpoint handling so
  tablets and phones no longer truncate text or overflow tables
  (issue #19).
- Responsive sweep round 2: adopt `ui_table` where raw `<table>` still
  lived in page code (settings SSH keys, application top-processes), add
  `sm` breakpoints to the page-level 4-stat grids (dashboard, server
  overview, app detail), and adopt `ui_kv_table` for the server-settings
  Connection block (issue #26).
- Updates tab flattened to match the Releases tab pattern and the Pencil
  design: drop the outer `ui_card` wrapper, lift "Available Updates" into
  a page-level section header, and let `ui_table` be the only card
  surface. Empty states stay wrapped so `ui_empty` keeps a frame.
- `ServerLive` render split into `server_live/view.ex` to stay under the
  ~500 LOC guardrail.

## [0.6.0] - 2026-05-22

### Added
- Persistent server metric history with tiered downsampling. New
  `server_stats` table plus `Stats.Collect`, `Stats.Downsample`, and
  `Stats.Prune` Oban workers wired into cron. Delta-aware parsers for
  `/proc/net/dev`, `/proc/diskstats`, and `df -P` feed counter-cache
  columns on `servers` (ADR 0010).
- Server detail page now renders CPU, memory, disk, and network charts
  via Chart.js, with a range dropdown driven by the downsampled tiers.
- Network throughput KPI replaces the load-average tile on server
  detail; CPU core count is surfaced alongside.
- `Mast.Release` runner, `mise` build tasks, and a plain-HTTP prod path
  for self-hosting.
- `MAST_PUBLIC_URL` + proxy-header trust toggle for deployments behind
  a reverse proxy.
- Boot-time validation that `MAST_VAULT_KEY` decodes to 32 bytes.
- Deployment guide and MIT license; project framed as personal-first.
- Releases are a first-class entity. Each Server hosts zero or
  more Releases, each with its own `release_command` and Log Source
  config. Adds a `releases` table, per-Release probes, per-Release
  Application ownership (`applications.release_id`), and a new
  `MastWeb.ReleaseLive` at `/servers/:id/releases/:name` with
  Overview / Logs / Settings sub-tabs (ADR 0008, issue #6).
- Live log streaming on the per-Release Logs tab. `Mast.Logs.Source`
  behaviour with `systemd` (`journalctl -u <unit> -f`) and `file`
  (`tail -n 200 -F`) adapters. Stream feeds a 1000-line ring buffer
  on the LiveView; `Mast.Logs.Janitor` cleans up orphaned remote
  processes when a LiveView dies abnormally.
- Per-Release "Probe Now" button on ReleaseLive for targeted refresh.
  Server-level "Probe All" still fans out across every Release on the
  Server.
- ServerLive "Releases" tab with add/remove flow, replacing the old
  per-server Apps tab. ServerLive Overview swaps the Apps card for a
  Releases card with per-Release status derived from each main app.
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
- `MastWeb.AppLive` renamed to `MastWeb.ApplicationLive` and nested
  under Server + Release at
  `/servers/:server_id/releases/:name/apps/:app_name`. Breadcrumb
  reflects the full hierarchy.
- Per-Application rows now belong to a Release (`applications.release_id`,
  unique on `(release_id, name)`), so two Releases on one Server can
  each have their own `logger`, `stdlib`, etc. without colliding.
- AppLive: removed the "Memory over time" placeholder card. The real
  chart lands when application sampling exists (issue #15).
- README: documents the `extra_applications: [:runtime_tools]`
  requirement and the graceful-fallback behaviour. New section
  documents the sudoers NOPASSWD entries Mast needs for journalctl
  and tail.
- ADR 0004: records the `:observer_backend` probe expression and its
  view-scoped invocation (mount + Refresh, not the 30s worker).

### Removed
- `servers.release_command` column and the App Monitoring card on
  ServerLive's Settings tab. Release-level config lives on
  ReleaseLive's Settings now.
- Server-level "Logs" tab. The patch-apply run log streaming
  infrastructure is still in place and will surface inline under the
  Updates tab in a follow-up. Per-Release Logs (ADR 0008) are the
  canonical Logs view.
- Old `/apps/:id` route.

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
