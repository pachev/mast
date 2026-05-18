defmodule Mast.Workers.ConnectionCheckTest do
  use Mast.DataCase, async: false
  use Oban.Testing, repo: Mast.Repo

  alias Mast.Fleet
  alias Mast.SSH.Stub
  alias Mast.Workers.ConnectionCheck

  @top_out """
  top - 10:42:00 up 1:00, 1 user, load average: 0.10, 0.10, 0.10
  Tasks: 100 total, 1 running, 99 sleeping
  %Cpu(s):  5.0 us,  2.0 sy,  0.0 ni, 90.0 id,  3.0 wa
  """

  @free_out """
                 total        used        free      shared  buff/cache   available
  Mem:            8000        2000        4000         100        2000        5500
  Swap:              0           0           0
  """

  @df_out """
  Filesystem      Size  Used Avail Use% Mounted on
  /dev/sda1        50G   12G   36G  26% /
  """

  @os_out """
  ID=ubuntu
  VERSION_ID="22.04"
  """

  setup do
    Stub.reset()
    :ok
  end

  @loadavg_out "0.42 0.55 0.61 2/123 12345\n"

  defp stub_healthy(server) do
    Stub.expect(server, "cat /etc/os-release", {:ok, @os_out})
    Stub.expect(server, "top -bn1 | head -3", {:ok, @top_out})
    Stub.expect(server, "free -m", {:ok, @free_out})
    Stub.expect(server, "df -h /", {:ok, @df_out})
    Stub.expect(server, "cat /proc/loadavg", {:ok, @loadavg_out})
  end

  describe "perform/1 with server_id" do
    test "marks server up and records metrics on success" do
      {:ok, server} = Fleet.create_server(%{name: "web-1", host: "10.0.0.7"})
      stub_healthy(server)

      assert :ok = perform_job(ConnectionCheck, %{"server_id" => server.id})

      reloaded = Fleet.get_server!(server.id)
      assert reloaded.status == "up"
      assert reloaded.os_id == "ubuntu"
      assert reloaded.package_manager == "apt"
      assert reloaded.cpu == 10.0
      assert reloaded.memory == 25.0
      assert reloaded.disk == 26.0
      assert reloaded.load_1 == 0.42
      assert reloaded.load_5 == 0.55
      assert reloaded.load_15 == 0.61
      assert reloaded.memory_total_mb == 8000
      assert reloaded.memory_used_mb == 2000
      assert reloaded.disk_total_gb == 50.0
      assert reloaded.disk_used_gb == 12.0
      assert reloaded.last_seen_at
      assert reloaded.unreachable_count == 0
    end

    test "marks server down when SSH fails" do
      {:ok, server} = Fleet.create_server(%{name: "web-2", host: "10.0.0.8"})
      # No stub responses registered — Stub returns {:error, :unexpected_command}

      assert :ok = perform_job(ConnectionCheck, %{"server_id" => server.id})

      reloaded = Fleet.get_server!(server.id)
      assert reloaded.status == "down"
      assert reloaded.unreachable_count == 1
    end

    test "broadcasts updated server on success" do
      {:ok, server} = Fleet.create_server(%{name: "web-3", host: "10.0.0.9"})
      stub_healthy(server)

      Phoenix.PubSub.subscribe(Mast.PubSub, "servers")

      assert :ok = perform_job(ConnectionCheck, %{"server_id" => server.id})

      assert_receive {:server_updated, updated}
      assert updated.id == server.id
      assert updated.status == "up"
    end
  end

  describe "perform/1 with all: true (cron)" do
    test "enqueues one ConnectionCheck per known server" do
      {:ok, s1} = Fleet.create_server(%{name: "a", host: "10.0.0.1"})
      {:ok, s2} = Fleet.create_server(%{name: "b", host: "10.0.0.2"})

      assert :ok = perform_job(ConnectionCheck, %{"all" => true})

      assert_enqueued(worker: ConnectionCheck, args: %{"server_id" => s1.id})
      assert_enqueued(worker: ConnectionCheck, args: %{"server_id" => s2.id})
    end
  end
end
