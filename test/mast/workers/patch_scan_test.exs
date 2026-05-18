defmodule Mast.Workers.PatchScanTest do
  use Mast.DataCase, async: false
  use Oban.Testing, repo: Mast.Repo

  alias Mast.Fleet
  alias Mast.SSH.Stub
  alias Mast.Workers.PatchScan

  setup do
    Stub.reset()
    :ok
  end

  @apt_out """
  Listing... Done
  openssl/jammy-updates 3.0.2-0ubuntu1.15 amd64 [upgradable from: 3.0.2-0ubuntu1.10]
  curl/jammy-updates 7.81.0-1ubuntu1.16 amd64 [upgradable from: 7.81.0-1ubuntu1.15]
  """

  describe "perform/1 with server_id" do
    test "scans apt server and stores updates_count + last_scan_at" do
      {:ok, server} =
        Fleet.create_server(%{name: "web-1", host: "10.0.0.7"})

      {:ok, server} =
        Fleet.update_server_meta(server, %{os_id: "ubuntu", package_manager: "apt"})

      Stub.expect(server, "sudo -n apt-get update -qq", {:ok, ""})
      Stub.expect(server, "LANG=C apt list --upgradable 2>/dev/null", {:ok, @apt_out})

      assert :ok = perform_job(PatchScan, %{"server_id" => server.id})

      s = Fleet.get_server!(server.id)
      assert s.updates_available == 2
      assert s.last_scan_at
    end

    test "no-op for servers without a known package manager" do
      {:ok, server} = Fleet.create_server(%{name: "x", host: "1.1.1.1"})
      # package_manager is nil — should skip without an SSH call.

      assert :ok = perform_job(PatchScan, %{"server_id" => server.id})

      s = Fleet.get_server!(server.id)
      assert s.updates_available == nil
      assert Stub.last_command(server) == nil
    end
  end

  describe "perform/1 with all: true" do
    test "fan-outs one job per server" do
      {:ok, s1} = Fleet.create_server(%{name: "a", host: "10.0.0.1"})
      {:ok, s2} = Fleet.create_server(%{name: "b", host: "10.0.0.2"})

      assert :ok = perform_job(PatchScan, %{"all" => true})

      assert_enqueued(worker: PatchScan, args: %{"server_id" => s1.id})
      assert_enqueued(worker: PatchScan, args: %{"server_id" => s2.id})
    end
  end
end
