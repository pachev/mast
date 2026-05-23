defmodule Mast.FleetStatsTest do
  use Mast.DataCase, async: true

  alias Mast.Fleet
  alias Mast.Fleet.Server
  alias Mast.Fleet.ServerStat

  defp server_fixture(attrs \\ %{}) do
    defaults = %{name: "srv-#{System.unique_integer([:positive])}", host: "10.0.0.1"}

    {:ok, server} =
      %Server{}
      |> Server.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    server
  end

  defp sample_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        bucket: "1m",
        recorded_at: DateTime.utc_now(),
        stats: %{"cpu" => 10.0, "memory" => 42.0}
      },
      overrides
    )
  end

  describe "record_sample/2" do
    test "persists a stat row for a server" do
      s = server_fixture()
      assert {:ok, %ServerStat{} = stat} = Fleet.record_sample(s, sample_attrs())
      assert stat.server_id == s.id
      assert stat.bucket == "1m"
      assert stat.stats["cpu"] == 10.0
    end

    test "returns changeset error on duplicate (server_id, bucket, recorded_at)" do
      s = server_fixture()
      at = DateTime.utc_now()
      attrs = sample_attrs(%{recorded_at: at})

      assert {:ok, _} = Fleet.record_sample(s, attrs)
      assert {:error, %Ecto.Changeset{} = cs} = Fleet.record_sample(s, attrs)
      refute cs.valid?
    end
  end

  describe "list_stats/3" do
    test "returns rows for the given server + bucket, ordered asc" do
      s = server_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      t1 = DateTime.add(now, -120, :second)
      t2 = DateTime.add(now, -60, :second)
      t3 = now

      {:ok, _} = Fleet.record_sample(s, sample_attrs(%{recorded_at: t2, stats: %{"cpu" => 2.0}}))
      {:ok, _} = Fleet.record_sample(s, sample_attrs(%{recorded_at: t1, stats: %{"cpu" => 1.0}}))
      {:ok, _} = Fleet.record_sample(s, sample_attrs(%{recorded_at: t3, stats: %{"cpu" => 3.0}}))

      rows = Fleet.list_stats(s.id, "1m", DateTime.add(now, -300, :second))
      assert Enum.map(rows, & &1.stats["cpu"]) == [1.0, 2.0, 3.0]
    end

    test "filters by bucket" do
      s = server_fixture()
      now = DateTime.utc_now()

      {:ok, _} = Fleet.record_sample(s, sample_attrs(%{bucket: "1m", recorded_at: now}))

      {:ok, _} =
        Fleet.record_sample(
          s,
          sample_attrs(%{bucket: "10m", recorded_at: DateTime.add(now, -60, :second)})
        )

      assert [%ServerStat{bucket: "1m"}] =
               Fleet.list_stats(s.id, "1m", DateTime.add(now, -3600, :second))
    end

    test "filters by since" do
      s = server_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      old = DateTime.add(now, -7200, :second)

      {:ok, _} = Fleet.record_sample(s, sample_attrs(%{recorded_at: old}))
      {:ok, _} = Fleet.record_sample(s, sample_attrs(%{recorded_at: now}))

      rows = Fleet.list_stats(s.id, "1m", DateTime.add(now, -3600, :second))
      assert length(rows) == 1
    end
  end
end
