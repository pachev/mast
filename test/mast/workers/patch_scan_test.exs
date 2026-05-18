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

      # Scan payload must use string keys so it round-trips through jsonb
      # and renders the same whether read from a broadcast or a refetch.
      assert %{"total" => 2, "updates" => updates} = s.last_scan
      assert [%{"package" => _, "new_version" => _} | _] = updates
    end

    test "broadcasts an updated server with string-keyed last_scan" do
      {:ok, server} = Fleet.create_server(%{name: "atomic", host: "1.1.1.10"})
      {:ok, server} = Fleet.update_server_meta(server, %{os_id: "ubuntu", package_manager: "apt"})

      Stub.expect(server, "sudo -n apt-get update -qq", {:ok, ""})
      Stub.expect(server, "LANG=C apt list --upgradable 2>/dev/null", {:ok, @apt_out})

      Phoenix.PubSub.subscribe(Mast.PubSub, "servers")

      assert :ok = perform_job(PatchScan, %{"server_id" => server.id})

      assert_receive {:server_updated, broadcast}
      assert %{"total" => 2, "updates" => [%{"package" => _} | _]} = broadcast.last_scan
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

  describe "audit logging" do
    test "writes a scan.run audit event on success" do
      {:ok, server} = Fleet.create_server(%{name: "audit-ok", host: "10.0.0.20"})
      {:ok, server} = Fleet.update_server_meta(server, %{os_id: "ubuntu", package_manager: "apt"})

      Stub.expect(server, "sudo -n apt-get update -qq", {:ok, ""})
      Stub.expect(server, "LANG=C apt list --upgradable 2>/dev/null", {:ok, @apt_out})

      :ok = perform_job(PatchScan, %{"server_id" => server.id})

      event =
        Mast.Audit.Event
        |> Mast.Repo.all()
        |> Enum.find(&(&1.event_type == "scan.run" and &1.subject_id == server.id))

      assert event
      assert event.metadata["outcome"] == "ok"
      assert event.metadata["updates_available"] == 2
    end

    test "writes a scan.run audit event on error" do
      {:ok, server} = Fleet.create_server(%{name: "audit-err", host: "10.0.0.21"})
      {:ok, server} = Fleet.update_server_meta(server, %{os_id: "ubuntu", package_manager: "apt"})

      Stub.expect(server, "sudo -n apt-get update -qq", {:error, :nxdomain})

      :ok = perform_job(PatchScan, %{"server_id" => server.id})

      event =
        Mast.Audit.Event
        |> Mast.Repo.all()
        |> Enum.find(&(&1.event_type == "scan.run" and &1.subject_id == server.id))

      assert event
      assert event.metadata["outcome"] == "error"
    end

    test "writes a scan.run audit event on skip" do
      {:ok, server} = Fleet.create_server(%{name: "audit-skip", host: "10.0.0.22"})

      :ok = perform_job(PatchScan, %{"server_id" => server.id})

      event =
        Mast.Audit.Event
        |> Mast.Repo.all()
        |> Enum.find(&(&1.event_type == "scan.run" and &1.subject_id == server.id))

      assert event
      assert event.metadata["outcome"] == "skip"
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
