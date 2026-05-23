defmodule Mast.Workers.StatsPruneTest do
  use Mast.DataCase, async: false
  use Oban.Testing, repo: Mast.Repo

  alias Mast.Fleet
  alias Mast.Fleet.ServerStat
  alias Mast.Workers.StatsPrune

  defp server_fixture do
    {:ok, server} =
      Fleet.create_server(%{name: "pr-#{System.unique_integer([:positive])}", host: "10.0.0.7"})

    server
  end

  defp insert_at(server, bucket, ago_seconds) do
    at =
      DateTime.utc_now() |> DateTime.add(-ago_seconds, :second) |> DateTime.truncate(:microsecond)

    {:ok, stat} =
      Fleet.record_sample(server, %{bucket: bucket, recorded_at: at, stats: %{"cpu" => 1.0}})

    stat
  end

  test "prunes 1m rows older than 1 hour and keeps recent ones" do
    server = server_fixture()
    old = insert_at(server, "1m", 3700)
    fresh = insert_at(server, "1m", 60)

    assert :ok = perform_job(StatsPrune, %{})

    ids = Repo.all(from s in ServerStat, select: s.id)
    refute old.id in ids
    assert fresh.id in ids
  end

  test "prunes 10m past 12h, 20m past 24h, 120m past 7d, 480m past 30d" do
    server = server_fixture()

    too_old = [
      {"10m", 12 * 3600 + 60},
      {"20m", 24 * 3600 + 60},
      {"120m", 7 * 86_400 + 60},
      {"480m", 30 * 86_400 + 60}
    ]

    fresh = [
      {"10m", 3600},
      {"20m", 12 * 3600},
      {"120m", 86_400},
      {"480m", 7 * 86_400}
    ]

    old_stats = Enum.map(too_old, fn {b, secs} -> insert_at(server, b, secs) end)
    fresh_stats = Enum.map(fresh, fn {b, secs} -> insert_at(server, b, secs) end)

    assert :ok = perform_job(StatsPrune, %{})
    ids = Repo.all(from s in ServerStat, select: s.id)

    for s <- old_stats, do: refute(s.id in ids, "expected #{s.bucket} (#{s.id}) pruned")
    for s <- fresh_stats, do: assert(s.id in ids, "expected #{s.bucket} kept")
  end

  test "is a no-op when there are no rows" do
    assert :ok = perform_job(StatsPrune, %{})
  end
end
