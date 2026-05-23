defmodule Mast.Fleet.DownsampleTest do
  use ExUnit.Case, async: true

  alias Mast.Fleet.Downsample
  alias Mast.Fleet.ServerStat

  describe "tier_transitions/0" do
    test "returns four transitions in order" do
      transitions = Downsample.tier_transitions()

      assert Enum.map(transitions, &{&1.source, &1.target}) == [
               {"1m", "10m"},
               {"10m", "20m"},
               {"20m", "120m"},
               {"120m", "480m"}
             ]

      assert Enum.map(transitions, & &1.factor) == [10, 2, 6, 4]
      assert Enum.map(transitions, & &1.target_minutes) == [10, 20, 120, 480]
    end
  end

  describe "bucket_floor/2" do
    test "floors a timestamp to the start of its 10-minute bucket" do
      dt = ~U[2026-05-22 12:07:33.456789Z]
      assert Downsample.bucket_floor(dt, 10) == ~U[2026-05-22 12:00:00.000000Z]
    end

    test "floors to start of 20-minute bucket" do
      dt = ~U[2026-05-22 12:25:00Z]
      assert Downsample.bucket_floor(dt, 20) == ~U[2026-05-22 12:20:00.000000Z]
    end

    test "floors to start of 120-minute bucket" do
      dt = ~U[2026-05-22 13:59:59Z]
      assert Downsample.bucket_floor(dt, 120) == ~U[2026-05-22 12:00:00.000000Z]
    end
  end

  describe "aggregate/1" do
    test "computes the mean of numeric leaves across input rows" do
      rows = [
        %ServerStat{stats: %{"cpu" => 10.0, "memory" => 50.0}},
        %ServerStat{stats: %{"cpu" => 20.0, "memory" => 60.0}},
        %ServerStat{stats: %{"cpu" => 30.0, "memory" => 70.0}}
      ]

      out = Downsample.aggregate(rows)
      assert out["cpu"] == 20.0
      assert out["memory"] == 60.0
    end

    test "averages disks list per mount key" do
      rows = [
        %ServerStat{
          stats: %{
            "disks" => [
              %{"mount" => "/", "used_pct" => 20.0, "total_gb" => 100.0, "used_gb" => 20.0},
              %{"mount" => "/data", "used_pct" => 50.0, "total_gb" => 500.0, "used_gb" => 250.0}
            ]
          }
        },
        %ServerStat{
          stats: %{
            "disks" => [
              %{"mount" => "/", "used_pct" => 40.0, "total_gb" => 100.0, "used_gb" => 40.0},
              %{"mount" => "/data", "used_pct" => 60.0, "total_gb" => 500.0, "used_gb" => 300.0}
            ]
          }
        }
      ]

      out = Downsample.aggregate(rows)
      root = Enum.find(out["disks"], &(&1["mount"] == "/"))
      data = Enum.find(out["disks"], &(&1["mount"] == "/data"))
      assert root["used_pct"] == 30.0
      assert root["used_gb"] == 30.0
      assert data["used_pct"] == 55.0
      assert data["used_gb"] == 275.0
    end

    test "ignores nil values per metric" do
      rows = [
        %ServerStat{stats: %{"cpu" => 10.0, "load_1" => nil}},
        %ServerStat{stats: %{"cpu" => 20.0, "load_1" => 2.0}}
      ]

      out = Downsample.aggregate(rows)
      assert out["cpu"] == 15.0
      assert out["load_1"] == 2.0
    end

    test "returns empty map for empty input" do
      assert Downsample.aggregate([]) == %{}
    end
  end
end
