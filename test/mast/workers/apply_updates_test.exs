defmodule Mast.Workers.ApplyUpdatesTest do
  use Mast.DataCase, async: false
  use Oban.Testing, repo: Mast.Repo

  alias Mast.Fleet
  alias Mast.Patches.Runs
  alias Mast.SSH.Stub
  alias Mast.Workers.ApplyUpdates

  setup do
    Stub.reset()
    :ok
  end

  describe "perform/1 — apply all" do
    test "streams output as PubSub events and triggers a rescan" do
      {:ok, server} = Fleet.create_server(%{name: "web-1", host: "10.0.0.7"})
      {:ok, server} = Fleet.update_server_meta(server, %{package_manager: "apt"})

      Stub.expect_stream(
        server,
        "sudo -n apt-get update -qq && sudo -n DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
        [
          {:line, :stdout, "Reading package lists...\n"},
          {:line, :stdout, "Setting up curl (7.81.0-1ubuntu1.16) ...\n"},
          {:exit, 0}
        ]
      )

      # ApplyUpdates triggers PatchScan after a successful apply.
      Stub.expect(server, "sudo -n apt-get update -qq", {:ok, ""})
      Stub.expect(server, "LANG=C apt list --upgradable 2>/dev/null", {:ok, "Listing... Done\n"})

      run_id = "test-run-1"
      topic = "runs:#{run_id}"
      Phoenix.PubSub.subscribe(Mast.PubSub, topic)

      assert :ok =
               perform_job(ApplyUpdates, %{
                 "server_id" => server.id,
                 "run_id" => run_id,
                 "scope" => "all"
               })

      # We expect each line + a final :exit event over PubSub.
      assert_receive {:run_event, ^run_id, {:line, :stdout, "Reading package lists...\n"}}, 1_000
      assert_receive {:run_event, ^run_id, {:line, :stdout, _}}, 1_000
      assert_receive {:run_event, ^run_id, {:exit, 0}}, 1_000

      # Side-effect: a PatchScan job should be enqueued for that server.
      assert_enqueued(worker: Mast.Workers.PatchScan, args: %{"server_id" => server.id})

      # Persistence: the run row holds the accumulated log + a done status.
      run = Runs.get_for_server(server.id)
      assert run.run_id == run_id
      assert run.status == "done"
      assert run.exit_code == 0
      assert run.log =~ "Reading package lists..."
      assert run.log =~ "Setting up curl"
    end

    test "persists an error run when the command exits non-zero" do
      {:ok, server} = Fleet.create_server(%{name: "web-fail", host: "10.0.0.8"})
      {:ok, server} = Fleet.update_server_meta(server, %{package_manager: "apt"})

      Stub.expect_stream(
        server,
        "sudo -n apt-get update -qq && sudo -n DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
        [
          {:line, :stderr, "E: Could not get lock\n"},
          {:exit, 100}
        ]
      )

      Stub.expect(server, "sudo -n apt-get update -qq", {:ok, ""})
      Stub.expect(server, "LANG=C apt list --upgradable 2>/dev/null", {:ok, "Listing... Done\n"})

      :ok =
        perform_job(ApplyUpdates, %{
          "server_id" => server.id,
          "run_id" => "fail-run",
          "scope" => "all"
        })

      run = Runs.get_for_server(server.id)
      assert run.status == "error"
      assert run.exit_code == 100
      assert run.log =~ "Could not get lock"
    end

    test "rejects servers without a supported package manager" do
      {:ok, server} = Fleet.create_server(%{name: "x", host: "1.1.1.1"})
      # package_manager nil.

      assert {:error, :unsupported_package_manager} =
               perform_job(ApplyUpdates, %{
                 "server_id" => server.id,
                 "run_id" => "r1",
                 "scope" => "all"
               })
    end
  end

  describe "perform/1 — apply one package" do
    test "rejects unsafe package names" do
      {:ok, server} = Fleet.create_server(%{name: "y", host: "1.1.1.2"})
      {:ok, server} = Fleet.update_server_meta(server, %{package_manager: "apt"})

      assert {:error, :invalid_package} =
               perform_job(ApplyUpdates, %{
                 "server_id" => server.id,
                 "run_id" => "r2",
                 "scope" => "package",
                 "package" => "foo; rm -rf /"
               })
    end

    test "runs apt install -y <package>" do
      {:ok, server} = Fleet.create_server(%{name: "z", host: "1.1.1.3"})
      {:ok, server} = Fleet.update_server_meta(server, %{package_manager: "apt"})

      Stub.expect_stream(
        server,
        "sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade openssl",
        [
          {:line, :stdout, "Setting up openssl ...\n"},
          {:exit, 0}
        ]
      )

      Stub.expect(server, "sudo -n apt-get update -qq", {:ok, ""})
      Stub.expect(server, "LANG=C apt list --upgradable 2>/dev/null", {:ok, "Listing... Done\n"})

      run_id = "r3"
      Phoenix.PubSub.subscribe(Mast.PubSub, "runs:#{run_id}")

      assert :ok =
               perform_job(ApplyUpdates, %{
                 "server_id" => server.id,
                 "run_id" => run_id,
                 "scope" => "package",
                 "package" => "openssl"
               })

      assert_receive {:run_event, ^run_id, {:line, :stdout, "Setting up openssl ...\n"}}
      assert_receive {:run_event, ^run_id, {:exit, 0}}
    end
  end

  describe "audit logging" do
    test "writes an apply.run audit event with exit code on success" do
      {:ok, server} = Fleet.create_server(%{name: "apply-audit", host: "10.0.0.30"})
      {:ok, server} = Fleet.update_server_meta(server, %{package_manager: "apt"})

      Stub.expect_stream(
        server,
        "sudo -n apt-get update -qq && sudo -n DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
        [{:exit, 0}]
      )

      Stub.expect(server, "sudo -n apt-get update -qq", {:ok, ""})
      Stub.expect(server, "LANG=C apt list --upgradable 2>/dev/null", {:ok, "Listing... Done\n"})

      :ok =
        perform_job(ApplyUpdates, %{
          "server_id" => server.id,
          "run_id" => "audit-run",
          "scope" => "all"
        })

      event =
        Mast.Audit.Event
        |> Mast.Repo.all()
        |> Enum.find(&(&1.event_type == "apply.run" and &1.subject_id == server.id))

      assert event
      assert event.metadata["outcome"] == "exit"
      assert event.metadata["exit_code"] == 0
      assert event.metadata["scope"] == "all"
    end

    test "writes an apply.run audit event when build fails (unsafe package)" do
      {:ok, server} = Fleet.create_server(%{name: "apply-bad", host: "10.0.0.31"})
      {:ok, server} = Fleet.update_server_meta(server, %{package_manager: "apt"})

      {:error, :invalid_package} =
        perform_job(ApplyUpdates, %{
          "server_id" => server.id,
          "run_id" => "audit-bad",
          "scope" => "package",
          "package" => "foo; rm -rf /"
        })

      event =
        Mast.Audit.Event
        |> Mast.Repo.all()
        |> Enum.find(&(&1.event_type == "apply.run" and &1.subject_id == server.id))

      assert event
      assert event.metadata["outcome"] == "error"
      assert event.metadata["reason"] =~ "invalid_package"
    end
  end
end
