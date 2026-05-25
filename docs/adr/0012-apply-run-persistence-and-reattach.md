# ADR 0012: Apply-run persistence and LiveView reattach

Status: Accepted
Date: 2026-05-25

## Context

"Apply updates" enqueues an Oban job (`Mast.Workers.ApplyUpdates`) that runs
`apt-get upgrade` over SSH and streams each output line to the browser over
PubSub (`runs:<run_id>`). Two problems shipped with the first cut:

1. **No output was ever rendered.** `ServerLive` set up a `:log` stream and
   appended every event to it, but no template rendered the stream. The only
   feedback was a "Running…" flash. An operator watching a real apply saw a
   spinner and silence, with no way to tell success from a hang. (Confirmed in
   the field: a `9 -> 3` apply on a host looked stuck the whole time.)

2. **A page reload orphaned the run.** `run_id` was generated per-mount. On
   reload the LiveView subscribed to a brand-new topic while the job kept
   broadcasting to the old one. The final `{:exit, 0}` went to nobody, so even
   the flash was lost. There was no way back to an in-flight run.

The streamed lines are ephemeral: once broadcast, they are gone. So
reconnecting a reloaded page to a running job requires *some* persistence.

## Decision

### Persist the last run per server in `patch_runs`

A new `patch_runs` table holds **one row per server** — the *last* run only.
`Mast.Patches.Runs.start_run/1` upserts on `server_id`, replacing the prior
row. Columns: `run_id`, `scope`, `package`, `status`
(`running | done | error`), `exit_code`, `error`, and the accumulated `log`
text.

We chose a dedicated table over columns on `servers` because a run has its own
lifecycle and the log is unbounded-ish (tens to low-hundreds of apt lines).
We chose one-row-per-server over a history table because the only consumer is
"reattach to the latest run"; run history is not a current requirement and a
unique index on `server_id` keeps the upsert trivial. A history table can come
later without touching callers if a need appears.

### Batch log writes, keep PubSub per-line

The worker still broadcasts every line immediately (live UX is cheap). DB
writes are **batched**: lines buffer and flush every 25, plus a final flush and
a status write when the stream closes. A reload mid-run sees everything
committed up to the last flush, which is plenty for apt-scale output. This
keeps the run a single Oban job with bounded write amplification rather than
one `UPDATE` per line.

### Reattach on mount

`ServerLive.mount/3` loads the server's last run:

- Subscribe to that run's `runs:<run_id>` topic (not a fresh one).
- Hydrate the `:log` stream from the stored `log` so output emitted before the
  reload is replayed.
- Auto-open the run-log modal **only if the run is still `running`**. Finished
  runs stay closed but their state is on record.

A new apply generates a fresh `run_id`, starts a new run row (replacing the
prior), and subscribes to the new topic.

### Reusable run-log modal

Output renders in a new `ui_run_log_modal` component (the `Modal/LogStream`
family in `components.pen`): a status badge (running / completed / failed), a
scrollable mono log region with a `RunLogAutoScroll` colocated hook, and a
Close/Done footer. The modal stays open on completion so the result is
reviewable; closing only hides it (the Oban job is not cancellable).

## Consequences

- A reloaded page reattaches to an in-flight apply and replays its log. The
  "looks stuck, no output" failure mode is gone.
- Hydrated lines lose their stdout/stderr/exit kind (we persist only text), so
  replayed output renders as plain stdout. Live lines keep their kind. This is
  an accepted fidelity loss for reattach.
- Persisted log is **not** decrypted SSH material and carries no secrets, so it
  is plain text (unlike key bodies, see ADR 0006). Operators should avoid apt
  hooks that echo secrets, same as any shell transcript.
- Only the last run survives. Closing the modal and starting another apply
  discards the previous run's log. Acceptable for now.
- No cancel: closing the modal hides it; the job runs to completion. Stopping a
  half-applied apt transaction is not something we want to expose yet.
