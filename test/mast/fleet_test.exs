defmodule Mast.FleetTest do
  use Mast.DataCase, async: true

  alias Mast.Fleet
  alias Mast.Fleet.Server

  @valid %{
    name: "web-1",
    host: "10.0.0.7",
    user: "ubuntu",
    port: 22
  }

  describe "create_server/1" do
    test "creates a server with valid attrs" do
      assert {:ok, %Server{} = s} = Fleet.create_server(@valid)
      assert s.name == "web-1"
      assert s.host == "10.0.0.7"
      assert s.user == "ubuntu"
      assert s.port == 22
      assert s.unreachable_count == 0
      assert s.status == "unknown"
    end

    test "defaults user to ubuntu and port to 22" do
      assert {:ok, s} = Fleet.create_server(%{name: "db", host: "10.0.0.8"})
      assert s.user == "ubuntu"
      assert s.port == 22
    end

    test "rejects blank name" do
      assert {:error, cs} = Fleet.create_server(%{name: "", host: "10.0.0.7"})
      assert "can't be blank" in errors_on(cs).name
    end

    test "rejects blank host" do
      assert {:error, cs} = Fleet.create_server(%{name: "x", host: ""})
      assert "can't be blank" in errors_on(cs).host
    end

    test "rejects bogus port" do
      assert {:error, cs} = Fleet.create_server(Map.put(@valid, :port, 0))
      assert errors_on(cs)[:port] != nil
    end

    test "rejects duplicate name" do
      assert {:ok, _} = Fleet.create_server(@valid)
      assert {:error, cs} = Fleet.create_server(@valid)
      assert "has already been taken" in errors_on(cs).name
    end
  end

  describe "list_servers/0" do
    test "returns servers ordered by name" do
      {:ok, _} = Fleet.create_server(%{name: "zeta", host: "10.0.0.9"})
      {:ok, _} = Fleet.create_server(%{name: "alpha", host: "10.0.0.7"})
      {:ok, _} = Fleet.create_server(%{name: "mike", host: "10.0.0.8"})

      assert ["alpha", "mike", "zeta"] = Enum.map(Fleet.list_servers(), & &1.name)
    end

    test "returns [] when empty" do
      assert [] = Fleet.list_servers()
    end
  end

  describe "get_server!/1" do
    test "returns server by id" do
      {:ok, s} = Fleet.create_server(@valid)
      assert Fleet.get_server!(s.id).name == "web-1"
    end
  end

  describe "delete_server/1" do
    test "removes a server" do
      {:ok, s} = Fleet.create_server(@valid)
      assert {:ok, _} = Fleet.delete_server(s)
      assert [] = Fleet.list_servers()
    end
  end

  describe "audit logging" do
    test "create_server writes a server.created audit event" do
      {:ok, s} = Fleet.create_server(@valid)

      [event] = Mast.Repo.all(Mast.Audit.Event)
      assert event.event_type == "server.created"
      assert event.subject_type == "Server"
      assert event.subject_id == s.id
      assert event.metadata["name"] == s.name
      assert event.metadata["host"] == s.host
    end

    test "create_server writes no audit event on failure" do
      {:error, _} = Fleet.create_server(%{name: "", host: ""})
      assert Mast.Repo.aggregate(Mast.Audit.Event, :count) == 0
    end

    test "delete_server writes a server.deleted audit event" do
      {:ok, s} = Fleet.create_server(@valid)
      {:ok, _} = Fleet.delete_server(s)

      events =
        Mast.Audit.Event
        |> Mast.Repo.all()
        |> Enum.map(& &1.event_type)

      assert "server.deleted" in events
    end
  end

  describe "record_metrics/2" do
    test "stores cpu/memory/disk/net snapshots and bumps last_seen_at" do
      {:ok, s} = Fleet.create_server(@valid)

      metrics = %{cpu: 19.8, memory: 28.1, disk: 7.5, net_mb_s: 0.0, agent_version: "0.1.0"}
      assert {:ok, s2} = Fleet.record_metrics(s, metrics)

      assert s2.cpu == 19.8
      assert s2.memory == 28.1
      assert s2.disk == 7.5
      assert s2.net_mb_s == 0.0
      assert s2.agent_version == "0.1.0"
      assert s2.status == "up"
      assert s2.unreachable_count == 0
      assert s2.last_seen_at
    end
  end

  describe "private_key association" do
    test "create_server accepts a private_key_id" do
      {:ok, key} =
        Mast.Keys.create_key(%{
          name: "ed25519 fixture",
          body: File.read!("test/fixtures/test_ed25519")
        })

      assert {:ok, server} =
               Fleet.create_server(%{
                 name: "with-key",
                 host: "10.0.0.7",
                 private_key_id: key.id
               })

      assert server.private_key_id == key.id
    end

    test "deleting a key nilifies private_key_id on referencing servers" do
      {:ok, key} =
        Mast.Keys.create_key(%{
          name: "k1",
          body: File.read!("test/fixtures/test_ed25519")
        })

      {:ok, server} =
        Fleet.create_server(%{name: "s1", host: "10.0.0.7", private_key_id: key.id})

      {:ok, _} = Mast.Keys.delete_key(key)

      reloaded = Fleet.get_server!(server.id)
      assert reloaded.private_key_id == nil
    end
  end

  describe "mark_unreachable/1" do
    test "increments counter and flips status to down" do
      {:ok, s} = Fleet.create_server(@valid)
      assert {:ok, s2} = Fleet.mark_unreachable(s)
      assert s2.unreachable_count == 1
      assert s2.status == "down"

      assert {:ok, s3} = Fleet.mark_unreachable(s2)
      assert s3.unreachable_count == 2
    end
  end
end
