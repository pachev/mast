defmodule Mast.Workers.StatsDownsampleTest do
  use Mast.DataCase, async: false
  use Oban.Testing, repo: Mast.Repo

  alias Mast.Fleet
  alias Mast.Fleet.ServerStat
  alias Mast.Workers.StatsDownsample

  defp server_fixture do
    {:ok, server} =
      Fleet.create_server(%{name: "ds-#{System.unique_integer([:positive])}", host: "10.0.0.7"})

    {:ok, server} = Fleet.record_metrics(server, %{cpu: 1.0})
    server
  end

  defp insert_sample(server, bucket, recorded_at, stats) do
    {:ok, _} =
      Fleet.record_sample(server, %{
        bucket: bucket,
        recorded_at: recorded_at,
        stats: stats
      })
  end

  describe "perform/1" do
    test "creates one 10m row from ten 1m rows in a complete window" do
      server = server_fixture()
      window_start = ~U[2026-05-22 12:00:00.000000Z]

      for i <- 0..9 do
        at = DateTime.add(window_start, i * 60, :second)
        insert_sample(server, "1m", at, %{"cpu" => i * 10 + 5.0})
      end

      # All 10 1m rows fall in the 12:00..12:10 window. Force "now" past the
      # window so the worker treats it as complete.
      assert :ok = perform_job(StatsDownsample, %{"now" => "2026-05-22T12:15:00Z"})

      [row] = Repo.all(from s in ServerStat, where: s.bucket == "10m")
      assert row.recorded_at == window_start
      # Mean of 5, 15, 25, ..., 95 = 50.0
      assert row.stats["cpu"] == 50.0
    end

    test "skips windows with fewer than the factor source rows" do
      server = server_fixture()
      window_start = ~U[2026-05-22 12:00:00.000000Z]

      for i <- 0..4 do
        at = DateTime.add(window_start, i * 60, :second)
        insert_sample(server, "1m", at, %{"cpu" => 10.0})
      end

      assert :ok = perform_job(StatsDownsample, %{"now" => "2026-05-22T12:15:00Z"})
      assert Repo.all(from s in ServerStat, where: s.bucket == "10m") == []
    end

    test "is idempotent — second run inserts zero rows" do
      server = server_fixture()
      window_start = ~U[2026-05-22 12:00:00.000000Z]

      for i <- 0..9 do
        at = DateTime.add(window_start, i * 60, :second)
        insert_sample(server, "1m", at, %{"cpu" => 10.0})
      end

      perform_job(StatsDownsample, %{"now" => "2026-05-22T12:15:00Z"})
      count_before = Repo.aggregate(from(s in ServerStat, where: s.bucket == "10m"), :count)

      perform_job(StatsDownsample, %{"now" => "2026-05-22T12:15:00Z"})
      count_after = Repo.aggregate(from(s in ServerStat, where: s.bucket == "10m"), :count)

      assert count_before == 1
      assert count_after == 1
    end

    test "does not aggregate a window whose end is in the future" do
      server = server_fixture()
      window_start = ~U[2026-05-22 12:00:00.000000Z]

      for i <- 0..9 do
        at = DateTime.add(window_start, i * 60, :second)
        insert_sample(server, "1m", at, %{"cpu" => 10.0})
      end

      # Now is 12:05 — window ends at 12:10, still in the future.
      assert :ok = perform_job(StatsDownsample, %{"now" => "2026-05-22T12:05:00Z"})
      assert Repo.all(from s in ServerStat, where: s.bucket == "10m") == []
    end

    test "cascade rolls 1m -> 10m -> 20m in a single run" do
      server = server_fixture()
      base = ~U[2026-05-22 12:00:00.000000Z]

      # 20 1m rows spanning two 10m windows.
      for i <- 0..19 do
        at = DateTime.add(base, i * 60, :second)
        insert_sample(server, "1m", at, %{"cpu" => 10.0})
      end

      assert :ok = perform_job(StatsDownsample, %{"now" => "2026-05-22T12:30:00Z"})

      assert Repo.aggregate(from(s in ServerStat, where: s.bucket == "10m"), :count) == 2
      assert Repo.aggregate(from(s in ServerStat, where: s.bucket == "20m"), :count) == 1
    end
  end
end
