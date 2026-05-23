defmodule MastWeb.Components.UI.Charts do
  @moduledoc """
  Server-rendered SVG charts. v1 of the server-detail metrics history
  panel uses pure SVG with no JS hook. A richer Canvas/Chart.js renderer
  is tracked as a follow-up issue.
  """
  use Phoenix.Component

  @viewbox_width 600
  @viewbox_height 160

  @doc """
  A minimal line chart. `points` is a list of `%{t: DateTime, v: number}`
  ordered ascending by `t`. `color` maps to a `--mast-chart-*` token.

  Empty input renders an empty-state. Single point renders a flat line.
  """
  attr :points, :list, required: true
  attr :color, :string, default: "blue"
  attr :label, :string, default: ""
  attr :unit, :string, default: ""

  def line_chart(assigns) do
    {polyline, min_v, max_v} = build_polyline(assigns.points)

    assigns =
      assigns
      |> assign(:polyline, polyline)
      |> assign(:min_v, min_v)
      |> assign(:max_v, max_v)
      |> assign(:viewbox, "0 0 #{@viewbox_width} #{@viewbox_height}")
      |> assign(:stroke_var, "var(--mast-chart-#{assigns.color})")

    ~H"""
    <div class="w-full">
      <%= if @points == [] do %>
        <div class="h-[180px] flex items-center justify-center rounded-[var(--radius-sm)] bg-[var(--mast-bg-secondary)] text-xs text-[var(--mast-font-tertiary)]">
          Collecting first sample...
        </div>
      <% else %>
        <svg
          viewBox={@viewbox}
          preserveAspectRatio="none"
          class="w-full h-[180px] rounded-[var(--radius-sm)] bg-[var(--mast-bg-secondary)]"
          aria-label={@label}
        >
          <polyline
            points={@polyline}
            fill="none"
            stroke={@stroke_var}
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
        <div class="flex justify-between text-[10px] text-[var(--mast-font-tertiary)] mt-1 px-1">
          <span>min {format_value(@min_v)}{@unit}</span>
          <span>max {format_value(@max_v)}{@unit}</span>
        </div>
      <% end %>
    </div>
    """
  end

  defp build_polyline([]), do: {"", 0.0, 0.0}

  defp build_polyline(points) do
    values = Enum.map(points, &numeric_v/1)
    min_v = Enum.min(values, fn -> 0.0 end) * 1.0
    max_v = Enum.max(values, fn -> 0.0 end) * 1.0
    span = if max_v - min_v == 0, do: 1.0, else: max_v - min_v

    n = length(points) - 1

    coords =
      points
      |> Enum.with_index()
      |> Enum.map(fn {%{} = p, i} ->
        x = if n == 0, do: @viewbox_width / 2, else: i / n * @viewbox_width
        v = numeric_v(p)
        y = @viewbox_height - (v - min_v) / span * @viewbox_height
        "#{Float.round(x, 2)},#{Float.round(y * 1.0, 2)}"
      end)

    {Enum.join(coords, " "), min_v, max_v}
  end

  defp numeric_v(%{v: v}) when is_number(v), do: v * 1.0
  defp numeric_v(_), do: 0.0

  defp format_value(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 1)
  defp format_value(v), do: to_string(v)
end
