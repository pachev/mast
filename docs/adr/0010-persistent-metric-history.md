# ADR 0010: Persistent metric history with tiered downsampling

Status: Accepted
Date: 2026-05-22

## Context

ADR 0005 declined a host-side agent and left long-term metric history as one
of the reasons we would reconsider that stance. We are now reconsidering it:
the server detail page needs CPU, memory, disk, disk I/O, network bandwidth,
and load-average charts across selectable time ranges (1h to 30d).

The `servers` row only stores the latest snapshot. Every 30s tick from
`Mast.Workers.ConnectionCheck` overwrites it. There is no history to chart.

We want history without taking on a host-side agent or a separate time-series
database. Stock Postgres can handle a personal/team fleet trivially.

## Decision

Add a `server_stats` table that stores periodic samples with **tiered
downsampling**, lifted from Beszel (`internal/records/records.go`). Plain
Postgres with a JSONB stats blob, indexed by `(server_id, bucket,
recorded_at)`, with a BRIN index on `recorded_at` for cheap retention
sweeps. No TimescaleDB, no extra service.

### Tiers

| Bucket | Retention | Source                       |
|--------|-----------|------------------------------|
| 1m     | 1 hour    | collector, one row per up server per minute |
| 10m    | 12 hours  | average of 10 x 1m           |
| 20m    | 1 day     | average of 2 x 10m           |
| 120m   | 7 days    | average of 6 x 20m           |
| 480m   | 30 days   | average of 4 x 120m          |

Steady-state per server: about 240 rows total across all tiers. Trivial.

### Workers

Three Oban crons under the existing `:checks` queue:

- `Mast.Workers.StatsCollect` (every minute) writes one `1m` row per up
  server. Pulls `top -bn1`, `free -m`, `df -P`, `/proc/net/dev`,
  `/proc/diskstats`, `/proc/loadavg` in a single combined `bash -c` heredoc.
  Computes per-second rates for bandwidth and disk I/O against counters
  cached on the `servers` row.
- `Mast.Workers.StatsDownsample` (every 10 minutes) walks the tier chain
  (`1m -> 10m -> 20m -> 120m -> 480m`) in one job. For each transition it
  groups complete source windows by bucket floor, averages numeric leaves
  (and `disks[]` per mount), and upserts via the unique index. Re-runs are
  no-ops.
- `Mast.Workers.StatsPrune` (hourly) deletes rows past their tier retention.

### Counter cache

To compute deltas for bandwidth and disk I/O, the previous raw counters need
to survive across ticks and across BEAM restarts. We store them as two
JSONB columns on the `servers` row: `last_net_counters` and
`last_disk_counters`. Atomic with the row update, no extra join, no ETS
fragility on restart.

### Live snapshot stays where it is

The fleet-list dashboard keeps reading the scalar metric columns on
`servers` (`cpu`, `memory`, `disk`, `load_*`). It does not query
`server_stats`. Two reasons: the snapshot card needs the freshest possible
read (no 10-minute smoothing), and a join per card is wasted work for the
"is it up?" view.

### Idempotency

The downsampler is idempotent through the unique index on
`(server_id, bucket, recorded_at)`. Downsampled rows use the bucket-floor of
the source window as their `recorded_at`. `INSERT ... ON CONFLICT DO NOTHING`
handles retries and partial completions.

### UI

Server detail page renders six charts (CPU, memory, disk, disk I/O,
bandwidth, load) as server-rendered SVG function components. A range
dropdown picks the lookback window and the bucket to read in one move
(1h -> 1m, 12h -> 10m, 24h -> 20m, 7d -> 120m, 30d -> 480m). Default is 1h.
SVG was picked for v1 simplicity. ADR 0011 records the follow-up
migration to a Chart.js + canvas renderer, which adds tooltips,
x-axis zoom, and multi-series overlays for rx/tx and read/write.

## Consequences

- One extra SSH session per server per minute on top of the existing
  liveness probe. Acceptable at our fleet size.
- Schema evolution of the stats blob is cheap (JSONB), but typed analytics
  queries on individual metrics are awkward. We accept that trade for
  storage simplicity. If we ever need fast per-metric SQL we add columns.
- ADR 0005 stands on the agent question. It is partially superseded only on
  the "no persistent history" point.
- The `:checks` Oban queue now handles three workers (ConnectionCheck,
  StatsCollect, plus the existing PatchScan). Concurrency stays at 5; we
  will raise it if collect runs start backing up.
- Mount-path is the join key for averaging `disks[]` on downsample. If a
  server remounts a filesystem under a different path, that mount's history
  effectively restarts. Acceptable.
- Counter wraparound on 32-bit kernel counters is handled by clamping
  negative deltas to 0, matching Beszel.
