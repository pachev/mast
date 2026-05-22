defmodule Mast.Workers.AppProbeTest do
  use Mast.DataCase, async: false
  use Oban.Testing, repo: Mast.Repo

  alias Mast.{Apps, Fleet}
  alias Mast.Apps.Probe.Stub
  alias Mast.Workers.AppProbe

  setup do
    Stub.reset()
    :ok
  end

  test "writes observations from the probe to the DB" do
    {:ok, server} = Fleet.create_server(%{name: "hermes", host: "10.0.0.1"})

    {:ok, release} =
      Fleet.create_release(%{
        server_id: server.id,
        release_command: "/opt/hermes/bin/hermes"
      })

    Stub.plant(
      release,
      {:ok,
       [
         %{
           name: "hermes",
           node_name: "hermes@host",
           version: "0.1.0",
           status: "running",
           memory_mb: 24.6,
           processes: 200,
           uptime_seconds: 3600
         }
       ]}
    )

    assert :ok = perform_job(AppProbe, %{"release_id" => release.id})

    [app] = Apps.list_for_server(server.id)
    assert app.name == "hermes"
    assert app.version == "0.1.0"
  end

  test "fan-out skips Releases with no release_command" do
    {:ok, srv1} = Fleet.create_server(%{name: "hermes", host: "10.0.0.1"})

    {:ok, with_cmd} =
      Fleet.create_release(%{
        server_id: srv1.id,
        release_command: "/opt/hermes/bin/hermes"
      })

    {:ok, srv2} = Fleet.create_server(%{name: "plain", host: "10.0.0.2"})

    {:ok, _logs_only} =
      Fleet.create_release(%{
        server_id: srv2.id,
        log_source: "file",
        log_target: "/var/log/app.log"
      })

    assert :ok = perform_job(AppProbe, %{"all" => true})

    assert_enqueued(worker: AppProbe, args: %{"release_id" => with_cmd.id})
    refute_enqueued(worker: AppProbe, args: %{"release_id" => nil})
  end

  test "probe failure does not crash the worker" do
    {:ok, server} = Fleet.create_server(%{name: "broken", host: "10.0.0.3"})

    {:ok, release} =
      Fleet.create_release(%{
        server_id: server.id,
        release_command: "/opt/broken/bin/broken"
      })

    Stub.plant(release, {:error, :ssh_failed})

    assert :ok = perform_job(AppProbe, %{"release_id" => release.id})
  end

  test "legacy server_id arg resolves the Server's first runnable Release" do
    {:ok, server} = Fleet.create_server(%{name: "legacy", host: "10.0.0.4"})

    {:ok, release} =
      Fleet.create_release(%{
        server_id: server.id,
        release_command: "/opt/legacy/bin/legacy"
      })

    Stub.plant(release, {:ok, [%{name: "legacy", node_name: "l@l", status: "running"}]})

    assert :ok = perform_job(AppProbe, %{"server_id" => server.id})
    assert [%{name: "legacy"}] = Apps.list_for_server(server.id)
  end
end
