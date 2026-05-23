defmodule MastWeb.Components.UI.Charts do
  @moduledoc """
  Canvas + Chart.js line charts. The hook is colocated below the markup
  so the JS lives next to the component. See ADR 0011.
  """
  use Phoenix.Component

  @doc """
  A line chart rendered via Chart.js. Accepts either:

    * `points` — `[%{t: DateTime, v: number}]`, single-series shape kept
      for backward compatibility with callers that pre-date multi-series.
    * `series` — `[%{name: string, color: string, points: [%{t, v}]}]`,
      one entry per overlaid line. Color names map to `--mast-chart-*`
      tokens.

  When both are empty, renders an empty-state placeholder.
  """
  attr :id, :string, required: true
  attr :points, :list, default: nil
  attr :series, :list, default: nil
  attr :color, :string, default: "blue"
  attr :label, :string, default: ""
  attr :unit, :string, default: ""
  attr :y_format, :string, default: "number", values: ~w(number percent mb_s)
  attr :since, :any, default: nil
  attr :until, :any, default: nil

  def line_chart(assigns) do
    series = encode_series(assigns)
    total_points = series |> Enum.map(&length(&1.points)) |> Enum.sum()
    # A line needs at least two points. One stray sample collapses the
    # x-axis to a millisecond span, so we show the empty-state instead.
    empty? = total_points < 2

    assigns =
      assigns
      |> assign(:series_json, Jason.encode!(series))
      |> assign(:empty?, empty?)
      |> assign(:since_ms, to_unix_ms(assigns[:since]))
      |> assign(:until_ms, to_unix_ms(assigns[:until]))

    ~H"""
    <div class="w-full">
      <%= if @empty? do %>
        <div class="h-[180px] flex items-center justify-center rounded-[var(--radius-sm)] bg-[var(--mast-bg-secondary)] text-xs text-[var(--mast-font-tertiary)]">
          Waiting for more samples...
        </div>
      <% else %>
        <div class="w-full h-[180px] relative">
          <canvas
            id={@id}
            phx-hook=".MetricChart"
            phx-update="ignore"
            data-series={@series_json}
            data-unit={@unit}
            data-y-format={@y_format}
            data-since={@since_ms}
            data-until={@until_ms}
            aria-label={@label}
            class="rounded-[var(--radius-sm)] bg-[var(--mast-bg-secondary)]"
          >
          </canvas>
        </div>
      <% end %>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".MetricChart">
      import Chart from "chart.js/auto"
      import zoomPlugin from "chartjs-plugin-zoom"
      import "chartjs-adapter-date-fns"

      Chart.register(zoomPlugin)

      function cssVar(name) {
        return getComputedStyle(document.documentElement).getPropertyValue(name).trim()
      }

      function fmtY(v, format) {
        if (v == null || isNaN(v)) return ""
        if (format === "percent") return `${Math.round(v)}`
        if (format === "mb_s") return v.toFixed(2)
        return Number.isInteger(v) ? v.toString() : v.toFixed(2)
      }

      export default {
        mounted() {
          this.render()
          this.el.addEventListener("dblclick", () => this.chart?.resetZoom())
        },
        updated() { this.render() },
        destroyed() { this.chart?.destroy() },
        render() {
          const series = JSON.parse(this.el.dataset.series)
          const unit = this.el.dataset.unit || ""
          const yFormat = this.el.dataset.yFormat || "number"
          const sinceMs = Number(this.el.dataset.since) || undefined
          const untilMs = Number(this.el.dataset.until) || undefined

          const datasets = series.map(s => {
            const color = cssVar(`--mast-chart-${s.color}`) || "#60a5fa"
            return {
              label: s.name,
              data: s.points.map(p => ({ x: new Date(p.t).getTime(), y: p.v })),
              borderColor: color,
              backgroundColor: color + "33",
              borderWidth: 2,
              pointRadius: 0,
              pointHoverRadius: 4,
              tension: 0.2,
              fill: false,
            }
          })

          if (this.chart) {
            this.chart.data.datasets = datasets
            this.chart.options.scales.x.min = sinceMs
            this.chart.options.scales.x.max = untilMs
            this.chart.update("none")
            return
          }

          const tickColor = cssVar("--mast-font-tertiary") || "#9ca3af"
          const gridColor = (cssVar("--mast-border") || "#374151") + "55"

          this.chart = new Chart(this.el, {
            type: "line",
            data: { datasets },
            options: {
              responsive: true,
              maintainAspectRatio: false,
              animation: false,
              parsing: false,
              interaction: { mode: "index", intersect: false },
              plugins: {
                legend: {
                  display: datasets.length > 1,
                  position: "top",
                  align: "end",
                  labels: { color: tickColor, boxWidth: 8, boxHeight: 8, font: { size: 10 } },
                },
                tooltip: {
                  mode: "index",
                  intersect: false,
                  callbacks: {
                    label: ctx => `${ctx.dataset.label}: ${fmtY(ctx.parsed.y, yFormat)}${unit}`,
                  },
                },
                zoom: {
                  zoom: {
                    drag: { enabled: true, backgroundColor: "rgba(96,165,250,0.15)" },
                    mode: "x",
                  },
                  pan: { enabled: false },
                },
              },
              scales: {
                x: {
                  type: "time",
                  min: sinceMs,
                  max: untilMs,
                  time: { tooltipFormat: "PPp" },
                  ticks: { color: tickColor, maxTicksLimit: 6, font: { size: 10 } },
                  grid: { color: gridColor },
                },
                y: {
                  beginAtZero: yFormat === "percent",
                  max: yFormat === "percent" ? 100 : undefined,
                  ticks: {
                    color: tickColor,
                    font: { size: 10 },
                    callback: v => fmtY(v, yFormat),
                  },
                  grid: { color: gridColor },
                },
              },
            },
          })
        },
      }
    </script>
    """
  end

  defp encode_series(%{series: list}) when is_list(list) and list != [] do
    Enum.map(list, fn s ->
      %{
        name: Map.get(s, :name, ""),
        color: Map.get(s, :color, "blue"),
        points: encode_points(Map.get(s, :points, []))
      }
    end)
  end

  defp encode_series(%{points: points} = a) when is_list(points) do
    [
      %{
        name: Map.get(a, :label, ""),
        color: Map.get(a, :color, "blue"),
        points: encode_points(points)
      }
    ]
  end

  defp encode_series(_), do: []

  defp encode_points(points) do
    points
    |> Enum.filter(fn p -> is_number(Map.get(p, :v)) end)
    |> Enum.map(fn %{t: t, v: v} -> %{t: encode_t(t), v: v} end)
  end

  defp encode_t(%DateTime{} = t), do: DateTime.to_iso8601(t)
  defp encode_t(%NaiveDateTime{} = t), do: NaiveDateTime.to_iso8601(t)
  defp encode_t(t), do: to_string(t)

  defp to_unix_ms(%DateTime{} = t), do: DateTime.to_unix(t, :millisecond)
  defp to_unix_ms(_), do: nil
end
