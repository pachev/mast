defmodule MastWeb.Components.UI.Data do
  @moduledoc """
  Data display: stats, metrics, tiles, key/value tables. The paginated
  table component lives in `MastWeb.Components.UI.Table`.
  """
  use Phoenix.Component

  @doc """
  Single KPI card: label + big number + optional trend/sub-label.

      <.ui_stat label="Total Servers" value={6} />
      <.ui_stat label="Online" value={5} tone="online" />
      <.ui_stat label="Updates Available" value={12} tone="warning" />
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sub, :string, default: nil
  attr :tone, :string, default: "default", values: ~w(default online warning offline accent)
  attr :progress, :integer, default: nil, doc: "0-100; when set, renders a usage bar"
  attr :bar_tone, :string, default: "accent", values: ~w(accent online warning offline)
  attr :class, :any, default: nil

  def ui_stat(assigns) do
    ~H"""
    <div class={[
      "bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
      "rounded-[var(--radius-box)] px-5 py-4 shadow-sm",
      @class
    ]}>
      <div class="text-xs font-medium uppercase tracking-wider text-[var(--mast-font-secondary)]">
        {@label}
      </div>
      <div class={["mt-1 text-3xl font-semibold tabular-nums leading-none", stat_tone(@tone)]}>
        {@value}
      </div>
      <div
        :if={is_integer(@progress)}
        class="mt-3 h-1.5 w-full rounded-full bg-[var(--mast-bg-tertiary)] overflow-hidden"
      >
        <div
          class={["h-full rounded-full", bar_color(@bar_tone)]}
          style={"width: #{max(0, min(100, @progress))}%"}
        />
      </div>
      <div :if={@sub} class="mt-2 text-xs text-[var(--mast-font-tertiary)]">
        {@sub}
      </div>
    </div>
    """
  end

  defp bar_color("online"), do: "bg-[var(--mast-status-online)]"
  defp bar_color("warning"), do: "bg-[var(--mast-status-warning)]"
  defp bar_color("offline"), do: "bg-[var(--mast-status-offline)]"
  defp bar_color(_), do: "bg-[var(--mast-accent)]"

  defp stat_tone("online"), do: "text-[var(--mast-status-online)]"
  defp stat_tone("warning"), do: "text-[var(--mast-status-warning)]"
  defp stat_tone("offline"), do: "text-[var(--mast-status-offline)]"
  defp stat_tone("accent"), do: "text-[var(--mast-accent)]"
  defp stat_tone(_), do: "text-[var(--mast-font-primary)]"

  @doc """
  Horizontal usage bar with leading numeric label.

      <.ui_metric label="CPU" value={68} />
      <.ui_metric label="Memory" value={9.4} max={16} suffix="GB" />
  """
  attr :label, :string, default: nil
  attr :value, :any, required: true
  attr :max, :integer, default: 100
  attr :suffix, :string, default: "%"
  attr :class, :any, default: nil

  def ui_metric(assigns) do
    pct = metric_pct(assigns.value, assigns.max)

    assigns =
      assigns
      |> assign(:pct, pct)
      |> assign(:tone, metric_tone(pct))

    ~H"""
    <div class={["space-y-1.5", @class]}>
      <div
        :if={@label}
        class="flex items-center justify-between text-xs text-[var(--mast-font-secondary)]"
      >
        <span>{@label}</span>
        <span class="tabular-nums font-medium text-[var(--mast-font-primary)]">
          {format_metric(@value, @suffix, @max)}
        </span>
      </div>
      <div class="h-1.5 rounded-full bg-[var(--mast-bg-tertiary)] overflow-hidden">
        <div
          class={["h-full rounded-full transition-all duration-300", @tone]}
          style={"width: #{@pct}%;"}
        />
      </div>
    </div>
    """
  end

  defp metric_pct(nil, _), do: 0

  defp metric_pct(v, max) when is_number(v) and is_number(max) and max > 0 do
    v |> Kernel./(max) |> Kernel.*(100) |> min(100) |> max(0)
  end

  defp metric_pct(_, _), do: 0

  defp metric_tone(pct) when pct >= 90, do: "bg-[var(--mast-status-offline)]"
  defp metric_tone(pct) when pct >= 75, do: "bg-[var(--mast-status-warning)]"
  defp metric_tone(_), do: "bg-[var(--mast-chart-blue)]"

  defp format_metric(nil, _, _), do: "—"

  defp format_metric(v, "%", _) when is_float(v),
    do: :erlang.float_to_binary(v, decimals: 1) <> "%"

  defp format_metric(v, "%", _), do: "#{v}%"

  defp format_metric(v, suffix, max) when is_number(v) and is_number(max) do
    "#{trim_num(v)} / #{trim_num(max)} #{suffix}"
  end

  defp format_metric(v, suffix, _), do: "#{v} #{suffix}"

  defp trim_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp trim_num(n), do: "#{n}"

  @doc """
  Card title row with an accent icon, label, and right-aligned count.
  Use as the title slot of `ui_card/1` when you want the design's icon-led
  card header style (e.g. Elixir Apps, Recent Logs).

      <.ui_card>
        <:title>
          <.ui_card_title icon="hero-cube" color="purple">
            Elixir Apps
            <:meta>3 running</:meta>
          </.ui_card_title>
        </:title>
        ...
      </.ui_card>
  """
  attr :icon, :string, required: true
  attr :color, :string, default: "purple", values: ~w(purple green blue orange accent)
  slot :inner_block, required: true
  slot :meta

  def ui_card_title(assigns) do
    ~H"""
    <span class="flex flex-wrap items-center gap-x-2 gap-y-1 w-full min-w-0">
      <span class={[@icon, "size-4 shrink-0", card_title_color(@color)]} />
      <span class="text-[14px] font-semibold text-[var(--mast-font-primary)] min-w-0 break-words">
        {render_slot(@inner_block)}
      </span>
      <span
        :if={@meta != []}
        class="text-[12px] text-[var(--mast-font-tertiary)] ml-auto whitespace-nowrap"
      >
        {render_slot(@meta)}
      </span>
    </span>
    """
  end

  defp card_title_color("purple"), do: "text-[var(--mast-chart-purple)]"
  defp card_title_color("green"), do: "text-[var(--mast-chart-green)]"
  defp card_title_color("blue"), do: "text-[var(--mast-chart-blue)]"
  defp card_title_color("orange"), do: "text-[var(--mast-chart-orange)]"
  defp card_title_color(_), do: "text-[var(--mast-accent)]"

  @doc """
  Single labeled metric tile (no bar). Used in dense metric rows like
  the Release card's Memory / Processes / Msg Queue strip.

      <.ui_metric_tile label="Memory" value="106 MB" />
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :class, :any, default: nil

  def ui_metric_tile(assigns) do
    ~H"""
    <div class={["flex-1 text-center", @class]}>
      <div class="text-[11px] text-[var(--mast-font-tertiary)] uppercase tracking-wider">
        {@label}
      </div>
      <div class="font-mono text-lg font-semibold text-[var(--mast-font-primary)] mt-1">
        {@value}
      </div>
    </div>
    """
  end

  @doc """
  Big-number stat tile (icon + label + mono value + sub-label). Designed
  for dense KPI rows on detail pages like ApplicationLive.

      <.ui_stat_tile icon="hero-cpu-chip" label="Memory" value="106.0 MB" sub="Total VM allocation" />
      <.ui_stat_tile label="Msg Queue" value="0" sub="Mailbox backlog" tone="accent" />
  """
  attr :icon, :string, default: nil
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sub, :string, default: nil
  attr :tone, :string, default: "default", values: ~w(default accent warning online offline)
  attr :class, :any, default: nil

  def ui_stat_tile(assigns) do
    ~H"""
    <div class={[
      "bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
      "rounded-[var(--radius-box)] p-5 shadow-sm",
      @class
    ]}>
      <div class="flex items-center gap-1.5 text-[var(--mast-font-secondary)]">
        <span :if={@icon} class={[@icon, "size-3.5"]} />
        <span class="text-xs font-medium uppercase tracking-wider">{@label}</span>
      </div>
      <div class={[
        "font-mono text-[28px] font-bold tabular-nums leading-tight mt-2",
        stat_tile_tone(@tone)
      ]}>
        {@value}
      </div>
      <div :if={@sub} class="text-[11px] text-[var(--mast-font-tertiary)] mt-1">
        {@sub}
      </div>
    </div>
    """
  end

  defp stat_tile_tone("accent"), do: "text-[var(--mast-accent)]"
  defp stat_tile_tone("warning"), do: "text-[var(--mast-status-warning)]"
  defp stat_tile_tone("online"), do: "text-[var(--mast-status-online)]"
  defp stat_tile_tone("offline"), do: "text-[var(--mast-status-offline)]"
  defp stat_tile_tone(_), do: "text-[var(--mast-font-primary)]"

  @doc """
  Key/value table inside a bordered card. Each row is a fixed 44px tall
  with a thin divider; the header row is 48px. Last row has no border.

      <.ui_kv_table title="Application Info">
        <:row label="Node">hermes@ip-...</:row>
        <:row label="Status">
          <.ui_badge variant="online">running</.ui_badge>
        </:row>
        <:row label="Version">0.1.0</:row>
      </.ui_kv_table>
  """
  attr :title, :string, required: true
  attr :class, :any, default: nil

  slot :row, required: true do
    attr :label, :string, required: true
  end

  def ui_kv_table(assigns) do
    ~H"""
    <div class={[
      "bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
      "rounded-[var(--radius-box)] overflow-hidden",
      @class
    ]}>
      <div class="h-12 px-5 flex items-center border-b border-[var(--mast-border)]">
        <h3 class="text-[14px] font-semibold text-[var(--mast-font-primary)]">{@title}</h3>
      </div>
      <div
        :for={{row, idx} <- Enum.with_index(@row)}
        class={[
          "py-2 sm:h-11 sm:py-0 px-5 flex flex-col sm:flex-row sm:items-center gap-1 sm:gap-4",
          idx < length(@row) - 1 && "border-b border-[var(--mast-border)]"
        ]}
      >
        <span class="text-[13px] font-medium text-[var(--mast-font-secondary)] sm:w-40 shrink-0">
          {row.label}
        </span>
        <span class="text-[13px] font-mono text-[var(--mast-font-primary)] flex-1 min-w-0 truncate">
          {render_slot(row)}
        </span>
      </div>
    </div>
    """
  end
end
