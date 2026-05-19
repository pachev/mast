# Mast UI Reference

This is the working reference for the Mast frontend. The source of truth
for visual design lives in `components.pen` (open with the Pencil app).
This document covers how those designs map to code so you can build new
LiveViews without re-deriving the system every time.

## TL;DR for new LiveViews

```heex
<Layouts.app flash={@flash} active="dashboard" page_title={@page_title}>
  <.ui_page_header title="My Page" subtitle="What this view does">
    <:actions>
      <.ui_button icon="hero-plus">New thing</.ui_button>
    </:actions>
  </.ui_page_header>

  <section class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
    <.ui_stat label="Total" value={42} />
  </section>

  <.ui_card>
    <:title>Section</:title>
    <:subtitle>Optional supporting copy</:subtitle>
    body...
  </.ui_card>
</Layouts.app>
```

Every component is imported automatically through `MastWeb` html_helpers,
so just call them. Form inputs still come from `MastWeb.CoreComponents`
(`<.input>`).

## Design tokens

Tokens live in `assets/css/app.css` and are exposed two ways:

1. **daisyUI theme variables** like `--color-primary`, `--color-base-100`.
   Use these through tailwind utilities such as `bg-primary`, `text-base-content`,
   or the daisyUI component classes (`btn`, `badge`, `alert`).
2. **Mast tokens** named `--mast-*`. Use these for anything that needs the
   specific design palette (`var(--mast-bg-card)`, `var(--mast-font-tertiary)`).
   Both light and dark themes resolve them automatically.

### Color tokens

| Token                  | Light       | Dark        | When to use                              |
| ---------------------- | ----------- | ----------- | ---------------------------------------- |
| `--mast-accent`        | `#4A7C59`   | `#8FBC8F`   | Primary actions, active nav, focus rings |
| `--mast-accent-muted`  | `#EDF3EF`   | `#1A2319`   | Tinted active surfaces                   |
| `--mast-bg-primary`    | `#F7F6F4`   | `#111210`   | Page background                          |
| `--mast-bg-card`       | `#FBFAF8`   | `#191917`   | Card / surface                           |
| `--mast-bg-sidebar`    | `#F1F0EC`   | `#131412`   | Sidebar background                       |
| `--mast-border`        | `#D8D6CE`   | `#2C2D28`   | All borders                              |
| `--mast-font-primary`  | `#111827`   | `#F1F5F9`   | Body text                                |
| `--mast-font-secondary`| `#6B7280`   | `#94A3B8`   | Labels, meta text                        |
| `--mast-font-tertiary` | `#9CA3AF`   | `#64748B`   | Placeholders, timestamps                 |
| `--mast-status-online` | `#3D8B4F`   | `#6DBF80`   | Online / success                         |
| `--mast-status-offline`| `#EF4444`   | `#F87171`   | Offline / error                          |
| `--mast-status-warning`| `#F59E0B`   | `#FBBF24`   | Warnings, attention                      |

### Spacing and radius

| Token            | Value | Use                                   |
| ---------------- | ----- | ------------------------------------- |
| `--spacing-xs`   | 4px   | Tight icon gaps                       |
| `--spacing-sm`   | 8px   | Default gap                           |
| `--spacing-md`   | 12px  | Card padding (top), button gaps       |
| `--spacing-lg`   | 16px  | Section internal padding              |
| `--spacing-xl`   | 24px  | Page padding                          |
| `--radius-sm`    | 4px   | Small buttons, checkbox               |
| `--radius-md`    | 8px   | Buttons, inputs (mapped to `--radius-field`) |
| `--radius-lg`    | 12px  | Cards, modals (mapped to `--radius-box`)     |

### Typography

- **Sans**: Inter, loaded from Google Fonts. Default for everything.
- **Mono**: JetBrains Mono. Use `font-mono` for hostnames, package names,
  IDs, timestamps in logs, version strings, anything that benefits from
  fixed-width.

Size scale (tailwind classes):

| Use             | Class       | Pencil equivalent |
| --------------- | ----------- | ----------------- |
| Page title      | `text-2xl`  | 24/600            |
| Card title      | `text-base` | 16/600            |
| Body            | `text-sm`   | 14/normal         |
| Label / meta    | `text-xs`   | 12/500            |
| Badge / tiny    | `text-[11px]` | 11/500          |

## Layout

### `Layouts.app/1`

The shell every LiveView wraps in. Renders the sidebar, the main column
padding, and the flash group.

```heex
<Layouts.app flash={@flash} active="dashboard" page_title={@page_title}>
  ...
</Layouts.app>
```

| Assign        | Type    | Notes                                                      |
| ------------- | ------- | ---------------------------------------------------------- |
| `flash`       | map     | Required. Pass `@flash` from the LiveView.                 |
| `active`      | string  | One of `dashboard`, `servers`, `apps`, `alerts`, `audit`, `settings`. Highlights the correct nav item. |
| `page_title`  | string  | Sets `<title>` via `live_title`.                           |
| `current_scope` | map   | Reserved for future authn scopes.                          |

### `ui_sidebar/1`

The sidebar component itself. `Layouts.app` already mounts one with the
real nav links and theme toggle, so you only call this directly when
building a custom shell.

```heex
<.ui_sidebar active="dashboard">
  <:nav key="dashboard" navigate={~p"/"} icon="hero-squares-2x2">Dashboard</:nav>
  <:nav key="servers" navigate={~p"/"} icon="hero-server-stack">Servers</:nav>
  <:footer>
    <.theme_toggle />
  </:footer>
</.ui_sidebar>
```

### `ui_page_header/1`

Page title row that sits at the top of the main column.

```heex
<.ui_page_header title="Fleet Overview" subtitle="6 servers · 5 online">
  <:actions>
    <.ui_search name="q" />
    <.ui_button icon="hero-plus">Add Server</.ui_button>
  </:actions>
</.ui_page_header>
```

## Primitives

### `ui_button/1`

```heex
<.ui_button>Save</.ui_button>
<.ui_button variant="secondary">Cancel</.ui_button>
<.ui_button variant="ghost" size="sm">Check</.ui_button>
<.ui_button variant="destructive" loading>Deleting...</.ui_button>
<.ui_button icon="hero-arrow-down-tray">Apply Updates</.ui_button>
<.ui_button navigate={~p"/"}>Home</.ui_button>
<.ui_button phx-click="save">Save</.ui_button>
```

| Attr       | Default     | Values                                        |
| ---------- | ----------- | --------------------------------------------- |
| `variant`  | `"primary"` | `primary`, `secondary`, `ghost`, `destructive` |
| `size`     | `"md"`      | `md`, `sm`                                    |
| `icon`     | nil         | Any `hero-*` icon name                        |
| `loading`  | `false`     | Shows spinner, disables button                |
| `disabled` | `false`     | Standard disabled state                       |

If you pass `href`, `navigate`, or `patch`, the button renders as a
`<.link>` so it keeps LiveView nav semantics.

### `ui_badge/1`

```heex
<.ui_badge variant="online">Online</.ui_badge>
<.ui_badge variant="warning">3 updates</.ui_badge>
<.ui_badge variant="neutral" dot={false}>v0.4.0</.ui_badge>
```

Variants: `online`, `offline`, `warning`, `neutral`, `accent`. The `dot`
flag toggles the leading status dot.

### `ui_status_dot/1`

Standalone status dot for use inline (server name rows, etc).

```heex
<.ui_status_dot status={@server.status} />
```

Recognized statuses: `up` / `online`, `down` / `offline`, `warning`.

### `ui_search/1`

Search-style input with leading magnifier icon. Self-styled, no form
field wrapping.

```heex
<form phx-change="filter">
  <.ui_search name="q" value={@filter} placeholder="Search servers..." class="w-64" />
</form>
```

For real form fields with labels and errors, use `<.input>` from
`MastWeb.CoreComponents`.

## Containers

### `ui_card/1`

The default surface for grouping content.

```heex
<.ui_card>
  <:title>Servers</:title>
  <:subtitle>6 across 3 regions</:subtitle>
  <:actions>
    <.ui_button size="sm">Add</.ui_button>
  </:actions>

  body content
</.ui_card>
```

Pass `padded={false}` if your content needs to span edge-to-edge (tables,
log panels, lists with internal padding).

### `ui_modal/1`

Centered modal. Pass a `JS` command to `on_cancel` so the modal can
dismiss via Escape, backdrop click, or the close button.

```heex
<.ui_modal :if={@show} id="confirm" on_cancel={JS.patch(~p"/")}>
  <:title>Delete server</:title>
  <:subtitle>This action cannot be undone.</:subtitle>

  Confirmation form here.

  <:footer>
    <.ui_button variant="secondary" phx-click={JS.patch(~p"/")}>Cancel</.ui_button>
    <.ui_button variant="destructive" phx-click="delete">Delete</.ui_button>
  </:footer>
</.ui_modal>
```

### `ui_empty/1`

Centered empty state.

```heex
<.ui_empty
  icon="hero-bell-slash"
  title="No alerts yet"
  body="When something needs attention, it'll show here."
>
  <.ui_button>Add Server</.ui_button>
</.ui_empty>
```

The inner block is optional and renders below the body, intended for one
or two CTA buttons.

### `ui_tabs/1`

Underlined tab bar. Drive it with a `tab` assign and either `phx-click`
events or `patch` navigation.

```heex
<.ui_tabs active={@tab}>
  <:tab key="overview" patch={~p"/servers/#{@id}?tab=overview"}>Overview</:tab>
  <:tab key="updates" patch={~p"/servers/#{@id}?tab=updates"} count={@count}>Updates</:tab>
</.ui_tabs>
```

The `count` slot attribute renders a pill on the right of the tab label.
For pure event-driven tabs, use `event="set-tab"` and handle
`set-tab` with the tab key in `handle_event/3`.

## Data display

### `ui_stat/1`

KPI tile, designed to live in a `grid` of 2 to 4 columns.

```heex
<.ui_stat label="Total Servers" value={6} />
<.ui_stat label="Online" value={5} tone="online" />
<.ui_stat label="Updates Available" value={12} tone="warning" sub="3 critical" />
```

Tones: `default`, `online`, `warning`, `offline`, `accent`.

### `ui_metric/1`

Horizontal progress bar with a numeric label.

```heex
<.ui_metric label="CPU" value={68} />
<.ui_metric label="Memory" value={9.4} max={16} suffix="GB" />
```

Color shifts automatically: green under 75%, amber 75 to 89%, red 90%+.

### `ui_server_card/1`

Server tile for the dashboard grid.

```heex
<.ui_server_card server={server} />
```

Expects a struct with `id`, `name`, `status`, `cpu`, `memory`, `disk`.
Wraps the whole card in a `<.link navigate={...}>` so the entire card is
clickable.

### `ui_app_card/1`

Single Elixir release card.

```heex
<.ui_app_card name="mast_web" version="0.4.0" status="running" uptime="12d" />
```

Statuses map to badges: `running` (online), `stopped` (offline), `pending`
(warning).

### `ui_table/1`

Paginated daisyUI table. Wrap the search input in a parent form with
`phx-change` to drive live filtering.

```heex
<form id="updates-filter" phx-change="filter-updates">
  <.ui_table id="updates" rows={@page_rows} size="sm">
    <:action_bar>
      <.ui_search name="q" value={@filter} placeholder="Filter packages..." />
      <span class="flex-1" />
      <span class="text-xs">{@total} packages</span>
    </:action_bar>

    <:col :let={row} label="Package">{row["package"]}</:col>
    <:col :let={row} label="Current">{row["current_version"]}</:col>
    <:col :let={row} label="New">{row["new_version"]}</:col>
    <:col :let={row} align="right">
      <.ui_button size="sm" variant="ghost" phx-click="apply" phx-value-name={row["package"]}>
        Apply
      </.ui_button>
    </:col>

    <:pagination
      page={@page}
      page_size={@page_size}
      total={@total}
      event="goto-page"
    />
  </.ui_table>
</form>
```

Attrs:

- `size`: `sm`, `md` (default), `lg`. Maps to daisyUI `table-sm|md|lg`.
- `zebra`: striped rows. Defaults to true (`table-zebra`).
- `pin_rows`: sticky header (`table-pin-rows`). Off by default.
- `empty`: copy shown when `rows` is empty.

The `:pagination` slot wires `phx-click={event}` with `phx-value-page=N` on
each button. The parent LiveView handles `goto-page` (or whatever you name
it) to update its page assign.

### `ui_log_entry/1`

One line in a streaming log panel. Designed to live inside a scroll
container with `font-mono` styling already applied.

```heex
<div id="log" phx-update="stream">
  <div :for={{dom_id, line} <- @streams.log} id={dom_id}>
    <.ui_log_entry kind={line.kind} time={line.time}>{line.data}</.ui_log_entry>
  </div>
</div>
```

Kinds: `:info`, `:stdout`, `:stderr`, `:exit`, `:error`. Colors map to
the status palette automatically.

### `ui_audit_row/1`

Row in an audit timeline. Each variant gets its own icon and badge color.

```heex
<.ui_audit_row
  variant="scan"
  actor="System"
  verb="scanned"
  target="web-prod-1"
  time="2m ago"
  detail="12 packages available"
/>
```

Variants: `action`, `scan`, `create`, `delete`, `failure`, `key-create`.

## Patterns

### Adding a new top-level page

1. Create the LiveView at `lib/mast_web/live/<name>_live.ex`.
2. Wrap `render/1` in `<Layouts.app flash={@flash} active="..." page_title={...}>`.
3. Add the route in `lib/mast_web/router.ex`.
4. Add a sidebar nav item in `Layouts.app` (already wired for `dashboard`,
   `servers`, `apps`, `alerts`, `audit`, `settings`).
5. Open the page once locally to confirm Tailwind picked up any new classes.

### Tabs that survive reload

Use `patch` navigation tied to a query param and read it in
`handle_params/3`. See `ServerLive` for a working example: the active tab
lives in `?tab=`, so deep links and refreshes keep state.

### Forms

Stick with `<.input>` from `MastWeb.CoreComponents` for form fields. It
gives you label + error rendering for free. Wrap the form in a
`<.ui_card>` or a `<.ui_modal>` depending on context. For non-form search
inputs, `<.ui_search>` is faster.

### Dark mode

Every Mast token has a dark counterpart already. As long as you reference
tokens (not raw colors) and use daisyUI utilities (`bg-base-100`, etc),
dark mode works without extra effort. The toggle is in the sidebar footer.

## Module map

The component library is split across `lib/mast_web/components/ui/` by
family. `MastWeb.Components.UI` is a thin `__using__` entrypoint that
imports every submodule, and `MastWeb` html_helpers does
`use MastWeb.Components.UI` so every `ui_*` function is available in
templates without imports.

| File | Components |
|------|-----------|
| `ui/buttons.ex` | `ui_button` |
| `ui/feedback.ex` | `ui_badge`, `ui_status_dot`, `ui_chip` |
| `ui/forms.ex` | `ui_search` |
| `ui/containers.ex` | `ui_card`, `ui_empty`, `ui_modal`, `ui_chart_card` |
| `ui/navigation.ex` | `ui_tabs`, `ui_sidebar`, `ui_page_header` |
| `ui/data.ex` | `ui_stat`, `ui_metric`, `ui_metric_tile`, `ui_stat_tile`, `ui_kv_table`, `ui_card_title` |
| `ui/table.ex` | `ui_table` |
| `ui/domain.ex` | `ui_server_card`, `ui_app_card`, `ui_app_row`, `ui_release_card`, `ui_log_entry`, `ui_audit_row` |
| `ui/js.ex` | `show/2`, `hide/2` |

## Adding new components

Add new function components to the right submodule under
`lib/mast_web/components/ui/` only when you've reused the same markup
three times. Until then, inline styles keep things easy to read. When
you do add one:

1. Name it `ui_<thing>/1`.
2. Drop it in the family file from the map above (create a new one if
   it genuinely doesn't fit and add it to the `__using__` macro in
   `ui.ex`).
3. Use tokens, never raw hex.
4. Add a doc-comment with at least one usage example.
5. Add a section in this document under the right category.

Heroicons are the default icon set. Reach for them via
`<span class="hero-name" />`. The full catalog is at
[heroicons.com](https://heroicons.com).
