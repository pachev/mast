# ADR 0009: Primary keys are UUIDs (binary_id)

Status: Accepted
Date: 2026-05-22

## Context

Up to v0.5, every application table used `bigserial` primary keys, the Ecto
and Phoenix default. That choice is fine for small single-tenant systems
but pinches in three places we already feel:

- **Polymorphic audit refs.** `audit_events.subject_id` points at either
  `servers.id`, `private_keys.id`, or `releases.id` depending on
  `subject_type`. Three sequences mean three independent integer spaces;
  a row with `subject_type="Server", subject_id=42` collides with
  `subject_type="PrivateKey", subject_id=42` in any analytical query that
  forgets the type guard. UUIDs make collisions per-table independent.
- **URL enumeration.** Today the dashboard exposes `/servers/7`, which leaks
  ordering and rough count to anyone with a viewing seat. UUIDs in URLs
  remove the side channel.
- **Cross-environment moves.** Restoring a prod dump into staging, or
  merging dev fixtures into another developer's database, currently
  requires renumbering. UUIDs make merges idempotent.

Issue #11 captured the decision to revisit and tracks the follow-up.

## Decision

### binary_id everywhere except Oban

All Mast-owned tables use `:binary_id` primary and foreign keys:

| Table | Old PK | New PK |
|---|---|---|
| `servers` | bigserial | uuid |
| `private_keys` | bigserial | uuid |
| `releases` | bigserial | uuid |
| `applications` | bigserial | uuid |
| `audit_events` | bigserial | uuid |

Foreign keys flip in lockstep:

- `servers.private_key_id`
- `releases.server_id`
- `applications.server_id`
- `applications.release_id`

The polymorphic refs on `audit_events` (`subject_id`, `actor_id`) also
flip to `uuid`. `actor_id` previously used `0` as a "System" sentinel; in
the binary_id world it is `NULL` instead, which is unambiguous and
removes the magic number.

UUIDs are generated server-side via Postgres `pgcrypto`'s
`gen_random_uuid()`. The migration enables the extension once.

### Oban stays bigint

Oban hard-codes `:bigserial` for `oban_jobs.id` and its engine queries
rely on bigint ordering and sequence semantics. Forking Oban's schema
would mean tracking upstream forever for a feature we do not need: job
ids never appear in URLs and have no foreign keys into Mast tables.

### Phoenix `--binary-id` shape

We use the exact pattern `mix phx.gen.schema --binary-id` would have
emitted, so future generators line up:

```elixir
@primary_key {:id, :binary_id, autogenerate: true}
@foreign_key_type :binary_id
schema "table_name" do
  # ...
end
```

And in migrations:

```elixir
create table(:foo, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :bar_id, references(:bars, on_delete: :delete_all, type: :binary_id)
end
```

`config/config.exs` sets `generators: [..., binary_id: true]` so anyone
running `mix phx.gen.context` or `mix phx.gen.auth` from now on gets the
right shape by default.

### Data-preserving conversion, one-way

The conversion migration (`20260522183428_convert_to_binary_ids`) adds
parallel `id_new`/`*_new` columns, populates them (PKs from
`gen_random_uuid()`, FKs via JOIN on the old integer id), drops the old
columns and constraints, then renames `id_new` into `id`. It is wrapped
in a single transaction so a failure rolls back cleanly.

For `audit_events.subject_id` the join runs once per known
`subject_type` (`Server`, `PrivateKey`, `Release`). Any rows with an
unknown type, or pointing at a deleted subject, land with
`subject_id = NULL`; the migration logs a warning summarising how many
rows fell into that bucket so operators know what they are looking at.

`def down` raises. uuid -> bigserial mapping is lossy and the issue
itself authorises a fresh-DB rollback path for operators who want one.

## Consequences

### Wins

- Audit log is honest about polymorphism. Cross-type id collisions are
  no longer possible.
- URLs no longer leak fleet size or insertion order.
- Cross-environment data movement is a `pg_dump | pg_restore` without
  sequence reset gymnastics.
- Future schemas pick up the right defaults from `:generators`. No
  per-PR reminder to add the `binary_id` flag.

### Costs

- Indexes are a little larger (16 bytes vs 8 bytes). Negligible at our
  scale, would matter for million-row hot paths.
- `Repo.get!/2` now accepts a UUID string directly, so LiveView mounts
  pass the raw `id` parameter through instead of `String.to_integer/1`.
  One Ecto behaviour to remember: `Repo.get!(Schema, "not-a-uuid")`
  raises `Ecto.Query.CastError`, which Phoenix translates into a 404
  via `Ecto.NoResultsError`-aware error views. Same shape callers
  expected before.
- The audit cursor decoder used `Integer.parse/1` on the id portion; it
  is now `Ecto.UUID.cast/1`. Existing cursors from before the cut are
  unusable, but cursors are URL-scoped state, not durable storage, so
  the breakage window is one open audit tab per operator.

### Migration risk

Single-tenant self-hosted today. The operator either runs the migration
on a fresh dev DB (zero risk) or on a small prod DB (one transaction,
seconds to complete at our row counts). The Oban carve-out keeps the job
queue running through the conversion without interruption.
