defmodule Mast.Fleet.ServerStatTest do
  use Mast.DataCase, async: true

  alias Mast.Fleet.ServerStat

  defp valid_attrs(overrides) do
    Map.merge(
      %{
        server_id: Ecto.UUID.generate(),
        bucket: "1m",
        recorded_at: DateTime.utc_now(),
        stats: %{"cpu" => 12.5}
      },
      overrides
    )
  end

  describe "changeset/2" do
    test "accepts known buckets" do
      for b <- ~w(1m 10m 20m 120m 480m) do
        cs = ServerStat.changeset(%ServerStat{}, valid_attrs(%{bucket: b}))
        assert cs.valid?, "expected #{b} to be valid"
      end
    end

    test "rejects unknown bucket" do
      cs = ServerStat.changeset(%ServerStat{}, valid_attrs(%{bucket: "5m"}))
      refute cs.valid?
      assert {_, _} = cs.errors[:bucket]
    end

    test "requires recorded_at" do
      cs = ServerStat.changeset(%ServerStat{}, valid_attrs(%{recorded_at: nil}))
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:recorded_at]
    end

    test "requires stats map" do
      cs = ServerStat.changeset(%ServerStat{}, valid_attrs(%{stats: nil}))
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:stats]
    end

    test "requires server_id" do
      cs = ServerStat.changeset(%ServerStat{}, valid_attrs(%{server_id: nil}))
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:server_id]
    end
  end
end
