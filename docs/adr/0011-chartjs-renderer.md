# ADR 0011: Chart.js renderer for server-detail metrics history

Status: Accepted
Date: 2026-05-22

## Context

ADR 0010 chose server-rendered SVG `<polyline>` for the six metrics-history
charts on the server-detail page. That was the v1 simplicity bet: zero JS
cost, no new dependency, charts render even with JS disabled. The trade
was no interactivity: no tooltip with the exact value at the cursor, no
way to zoom into a window of interest, and no way to show two related
series on one canvas (rx/tx, read/write).

We already had the data needed for richer charts (per-second byte rates
for rx and tx separately, etc.), so the SVG view was selling the data
short. Issue #22 captured the follow-up.

## Decision

### Chart.js v4, not a hand-rolled Canvas renderer

The features the issue asks for (index-mode tooltips across multiple
datasets, click-drag x-zoom, time-scale gridlines, responsive resize)
are all out-of-the-box Chart.js. Writing them by hand against
`<canvas>` would burn weeks for the same result.

We import `chart.js/auto`, `chartjs-plugin-zoom`, and
`chartjs-adapter-date-fns` from npm. The minified bundle for `app.js`
grows from roughly 290 kB to roughly 970 kB. Acceptable for a
self-hosted dashboard whose users sit on the same LAN as the server.
If the bundle ever becomes a real cost we can switch to controller
registration (`Chart.register(LineController, ...)`) and shed about
40% of the Chart.js footprint.

### Phoenix Colocated Hook

The hook lives inside `lib/mast_web/components/ui/charts.ex` as a
`<script :type={Phoenix.LiveView.ColocatedHook} name=".MetricChart">`
block. JS sits next to the markup that owns it. Phoenix prefixes the
name with the module at compile time, which avoids global-name
collisions and means there is no `assets/js/hooks/` directory to wire
up by hand. `mix compile` writes the manifest at
`_build/<env>/phoenix-colocated/mast/index.js`, which `app.js` already
imports.

The canvas carries `phx-update="ignore"` so LiveView never touches the
DOM the hook owns. Series data flows as a JSON-encoded `data-series`
attribute, read on `mounted()` and `updated()`. The hook calls
`chart.update("none")` so range changes do not animate.

### Build ordering

`mix assets.build` and `mix assets.deploy` already run `compile` before
esbuild, so the colocated manifest exists before bundling. `mise run
release` chains `release:compile -> release:assets -> release`, so the
same applies in prod. Node 22 is added to `mise.toml` `[tools]` so
`npm install` works on fresh checkouts.

### Multi-series instead of summing

The bandwidth and disk-I/O charts used to sum the two underlying
series in the LiveView (`combine_pair/3`) and hand the chart a single
line. We now pass two datasets per chart. The total is reconstructable
from the tooltip; the per-series visibility is the whole point of the
upgrade.

### Local zoom only

Click-drag zooms within the data already in the browser. We do not
re-query the server for a finer bucket when zoomed. The range dropdown
remains the way to ask for a different time window from Postgres. This
keeps the LiveView side unchanged and avoids the dance of mapping a
canvas-pixel x range back to a `since`/`bucket` query.

Double-click on the canvas calls `chart.resetZoom()`. We can revisit
adding a visible button if double-click turns out to be undiscoverable.

## Consequences

- Bundle size grows by roughly 700 kB. Tracked, not fixed today.
- The component API gained `id` (required, for canvas DOM identity),
  `series` (multi-series shape), and `y_format` (`"number" | "percent" |
  "mb_s"`). The original `points` shape still works for the four
  single-series cards.
- Server-side `combine_pair/3` was deleted. The two callers now pass
  two datasets directly.
- Chart.js needs a date adapter for the `time` scale, so
  `chartjs-adapter-date-fns` and `date-fns` are now transitive deps.
  Imported once inside the hook.
- The minimum runtime stack now includes Node (for `npm install`).
  Added to `mise.toml` rather than left as a hidden host dependency.
- Visual regression coverage is manual: hover a chart, drag to zoom,
  double-click to reset, switch the range dropdown. Unit tests cover
  the markup contract (canvas with the right `phx-hook` and
  `data-series` JSON), not the rendered pixels.
