defmodule MastWeb.Components.UI.ChartsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MastWeb.Components.UI.Charts

  defp html_attr_decode(s) do
    s
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end

  describe "line_chart/1 (canvas + Chart.js hook)" do
    test "renders empty-state placeholder when all series are empty" do
      html =
        render_component(&Charts.line_chart/1, %{
          id: "chart-empty",
          points: [],
          color: "blue",
          label: "CPU %"
        })

      assert html =~ "Waiting for more samples"
      refute html =~ "<canvas"
    end

    test "renders a canvas wired to the colocated hook for a single series" do
      now = DateTime.utc_now()

      points =
        for i <- 0..2 do
          %{t: DateTime.add(now, -i * 60, :second), v: i * 10.0}
        end

      html =
        render_component(&Charts.line_chart/1, %{
          id: "chart-cpu",
          points: points,
          color: "blue",
          label: "CPU %",
          unit: "%",
          y_format: "percent"
        })

      assert html =~ ~s(id="chart-cpu")
      assert html =~ ~s(<canvas)
      # Phoenix prefixes colocated hook names with the module at compile time,
      # so the rendered attribute is the fully-qualified name.
      assert html =~ ~s(phx-hook=")
      assert html =~ "MetricChart"
      assert html =~ ~s(phx-update="ignore")
      assert html =~ ~s(data-unit="%")
      assert html =~ ~s(data-y-format="percent")

      data_series =
        Regex.run(~r/data-series="([^"]+)"/, html)
        |> case do
          [_, s] -> s
          _ -> flunk("data-series attribute missing")
        end

      decoded =
        data_series
        |> html_attr_decode()
        |> Jason.decode!()

      assert [%{"name" => "CPU %", "color" => "blue", "points" => series_points}] = decoded
      assert length(series_points) == 3
      assert Enum.all?(series_points, &Map.has_key?(&1, "t"))
      assert Enum.all?(series_points, &Map.has_key?(&1, "v"))
    end

    test "passes through multi-series shape verbatim" do
      now = DateTime.utc_now()

      rx = [%{t: now, v: 1.0}, %{t: DateTime.add(now, -60, :second), v: 2.0}]
      tx = [%{t: now, v: 3.0}]

      html =
        render_component(&Charts.line_chart/1, %{
          id: "chart-bw",
          series: [
            %{name: "rx", color: "blue", points: rx},
            %{name: "tx", color: "purple", points: tx}
          ],
          unit: " MB/s",
          y_format: "mb_s"
        })

      assert html =~ ~s(<canvas)

      data_series =
        Regex.run(~r/data-series="([^"]+)"/, html)
        |> case do
          [_, s] -> s
          _ -> flunk("data-series attribute missing")
        end

      decoded =
        data_series
        |> html_attr_decode()
        |> Jason.decode!()

      assert [
               %{"name" => "rx", "color" => "blue", "points" => rx_pts},
               %{"name" => "tx", "color" => "purple", "points" => tx_pts}
             ] = decoded

      assert length(rx_pts) == 2
      assert length(tx_pts) == 1
    end

    test "treats multi-series with all-empty point lists as empty" do
      html =
        render_component(&Charts.line_chart/1, %{
          id: "chart-bw-empty",
          series: [
            %{name: "rx", color: "blue", points: []},
            %{name: "tx", color: "purple", points: []}
          ]
        })

      assert html =~ "Waiting for more samples"
      refute html =~ "<canvas"
    end
  end
end
