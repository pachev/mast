# ADR 0007: Audit log from day one

Status: Accepted
Date: 2026-05-18

## Context

ADR 0006 deferred the audit log "until there is a user account model to
attribute actions to." That was the wrong call. The data you want from an
audit log (when was this key created, when did apply-updates run on which
box, what was the outcome) is impossible to backfill. By the time accounts
arrive, the history we care about is already gone.

We want the table populated from v0.4 onward. `actor_id` can stay null-ish
until accounts land; everything else (`event_type`, `subject_type`,
`subject_id`, `metadata`, `inserted_at`) is useful immediately.

## Decision

### Append-only schema

```
audit_events
  - id              bigserial
  - event_type      string, not null     # "key.created", "server.added", …
  - actor_id        bigint, nullable     # defaults to 0 ("System") today
  - subject_type    string               # "PrivateKey", "Server"
  - subject_id      bigint               # integer FK by convention, no DB FK
  - metadata        jsonb, default '{}'
  - inserted_at     timestamptz, not null
```

No `updated_at`. Rows are never modified after insert. The "System" actor
id is `0`, defined by `Mast.Audit.Event.system_actor_id/0`; once real
accounts exist a `scope_to_actor_fields/1` helper will set the real id.

Indexes: `(subject_type, subject_id)`, `(event_type, inserted_at desc)`,
and `(inserted_at desc)` for the recent-events view. No FK to servers or
private_keys: we want audit rows to survive their subject being deleted.

### Two-function context: `log/1` and `multi_log/3`

`Mast.Audit.log/1` does a single insert. Never raises. On failure it logs
`Logger.error` and returns `{:error, changeset}` so the caller decides
what to do. Used by background workers where the audited action (an SSH
command) happens outside any DB transaction.

`Mast.Audit.multi_log/3` inserts the event inside an `Ecto.Multi` so the
audit row and the business row commit atomically. Used by `Mast.Keys` and
`Mast.Fleet` so a `key.created` event can never exist without the matching
`private_keys` row (and vice versa).

This mirrors `Mangrove.Audit` in the family-friendly project — same shape,
same contract, minus the scope/role layer Mast doesn't have yet.

### Events logged in v0.4

| event_type | site |
|---|---|
| `key.created` | `Mast.Keys.create_key/1` |
| `key.deleted` | `Mast.Keys.delete_key/1` |
| `server.created` | `Mast.Fleet.create_server/1` |
| `server.deleted` | `Mast.Fleet.delete_server/1` |
| `scan.run` | `Mast.Workers.PatchScan.perform/1` (ok / error / skip) |
| `apply.run` | `Mast.Workers.ApplyUpdates.perform/1` (exit code / error) |

### No UI yet

Issue 3 explicitly defers the UI. A `/audit` LiveView lands in a later PR
once we know what queries are actually useful. The data is on disk from
day one regardless.

## Consequences

- Every meaningful state change in Mast now leaves a row. Disk grows
  bounded by operator activity, not telemetry volume.
- `Mast.Fleet.create_server/1`, `Mast.Fleet.delete_server/1`,
  `Mast.Keys.create_key/1`, and `Mast.Keys.delete_key/1` now run inside a
  transaction. Tests asserting their return tuples are unchanged.
- `subject_id` is `:bigint` and matches Mast's integer ids. If we ever
  move to UUIDs (see follow-up issue), the audit column migrates along
  with the rest in one pass.
- Background workers swallow audit failures (logged, not raised). A
  failed audit insert does not abort an apply-updates run; the broken
  audit is loud in logs.

## What we explicitly did NOT decide here

- **Retention policy.** Today we keep everything. A future ADR will add a
  prune job once the table is large enough to care about.
- **Actor model.** `actor_id` is 0 (System) until real accounts exist.
  The column is `:bigint, nullable` so we can flip semantics without a
  type change.
- **Streaming to an external sink** (S3, syslog). Local DB only for now.
