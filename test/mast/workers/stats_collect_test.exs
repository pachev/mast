defmodule Mast.Workers.StatsCollectTest do
  use Mast.DataCase, async: false
  use Oban.Testing, repo: Mast.Repo

  alias Mast.Fleet
  alias Mast.Fleet.ServerStat
  alias Mast.SSH.Stub
  alias Mast.Workers.StatsCollect

  @net_dev File.read!("test/support/fixtures/proc/net_dev.txt")
  @diskstats File.read!("test/support/fixtures/proc/diskstats.txt")
  @df_p File.read!("test/support/fixtures/proc/df_p.txt")

  @top "top - 1:00 up 1:00\nTasks: 1\n%Cpu(s):  5.0 us,  2.0 sy,  0.0 ni, 90.0 id,  3.0 wa\n"
  @free "             total used free shared buff/cache available\nMem:   8000 2000 4000 100 2000 5500\nSwap: 0 0 0\n"
  @loadavg "0.42 0.55 0.61 2/123 12345\n"

  defp combined_output do
    [
      "__TOP__",
      @top,
      "__FREE__",
      @free,
      "__DF__",
      @df_p,
      "__NET__",
      @net_dev,
      "__IO__",
      @diskstats,
      "__LOAD__",
      @loadavg
    ]
    |> Enum.join("\n")
  end

  setup do
    Stub.reset()

    {:ok, server} =
      Fleet.create_server(%{
        name: "stats-#{System.unique_integer([:positive])}",
        host: "10.0.0.7"
      })

    {:ok, server} = Fleet.record_metrics(server, %{cpu: 1.0})
    {:ok, server: server}
  end

  defp stub_combined(server, output \\ nil) do
    out = output || combined_output()
    Stub.expect(server, StatsCollect.command(), {:ok, out})
  end

  describe "perform/1 with server_id" do
    test "writes a 1m row and primes counter caches when prev is nil", %{server: server} do
      stub_combined(server)
      assert :ok = perform_job(StatsCollect, %{"server_id" => server.id})

      assert [%ServerStat{} = stat] = Repo.all(ServerStat)
      assert stat.server_id == server.id
      assert stat.bucket == "1m"
      assert stat.stats["cpu"] == 10.0
      assert stat.stats["rx_bytes_s"] == 0.0
      assert stat.stats["tx_bytes_s"] == 0.0
      assert is_list(stat.stats["disks"])
      assert is_number(stat.stats["load_1"])

      reloaded = Fleet.get_server!(server.id)
      assert is_map(reloaded.last_net_counters)
      assert is_map(reloaded.last_disk_counters)
    end

    test "skips servers with status other than up", %{server: server} do
      {:ok, _} = Fleet.mark_unreachable(server)
      assert :ok = perform_job(StatsCollect, %{"server_id" => server.id})
      assert Repo.all(ServerStat) == []
    end

    test "SSH failure does not insert a row and does not clobber counters", %{server: server} do
      {:ok, _} =
        Fleet.update_counters(server, %{
          last_net_counters: %{
            "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "ifaces" => %{"eth0" => %{"rx" => 1, "tx" => 2}}
          }
        })

      Stub.expect(server, StatsCollect.command(), {:error, :nxdomain})
      assert :ok = perform_job(StatsCollect, %{"server_id" => server.id})

      assert Repo.all(ServerStat) == []
      reloaded = Fleet.get_server!(server.id)
      assert reloaded.last_net_counters["ifaces"]["eth0"]["rx"] == 1
    end
  end

  describe "perform/1 with all: true" do
    test "fans out one job per up server", %{server: server} do
      {:ok, down_server} =
        Fleet.create_server(%{
          name: "down-#{System.unique_integer([:positive])}",
          host: "10.0.0.8"
        })

      {:ok, _} = Fleet.mark_unreachable(down_server)

      assert :ok = perform_job(StatsCollect, %{"all" => true})

      jobs = all_enqueued(worker: StatsCollect)
      assert Enum.any?(jobs, &(&1.args["server_id"] == server.id))
      refute Enum.any?(jobs, &(&1.args["server_id"] == down_server.id))
    end
  end
end
