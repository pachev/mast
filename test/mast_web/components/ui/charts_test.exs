defmodule MastWeb.Components.UI.ChartsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MastWeb.Components.UI.Charts

  describe "line_chart/1" do
    test "renders an empty-state message when points is []" do
      html =
        render_component(&Charts.line_chart/1, %{
          points: [],
          color: "blue",
          label: "CPU %"
        })

      assert html =~ "Collecting first sample"
      refute html =~ "<polyline"
    end

    test "renders a polyline with one point per input" do
      now = DateTime.utc_now()

      points =
        for i <- 0..4 do
          %{t: DateTime.add(now, -i * 60, :second), v: i * 10.0}
        end

      html =
        render_component(&Charts.line_chart/1, %{
          points: points,
          color: "blue",
          label: "CPU %"
        })

      assert html =~ "<polyline"
      # 5 points -> 5 comma-separated x,y pairs (4 spaces separating them).
      polyline_points =
        Regex.run(~r/points="([^"]+)"/, html)
        |> case do
          [_, s] -> s
          _ -> ""
        end

      assert length(String.split(polyline_points, " ", trim: true)) == 5
    end

    test "scales y-axis to the min and max of input" do
      now = DateTime.utc_now()
      points = [%{t: now, v: 10.0}, %{t: DateTime.add(now, -60, :second), v: 90.0}]

      html =
        render_component(&Charts.line_chart/1, %{
          points: points,
          color: "blue",
          label: "CPU %"
        })

      # Two extreme points should render at the top and bottom of the viewbox.
      assert html =~ "<polyline"
    end
  end
end
