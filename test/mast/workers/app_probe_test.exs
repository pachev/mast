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
    {:ok, server} = Fleet.update_monitoring(server, %{release_command: "/opt/hermes/bin/hermes"})

    Stub.plant(
      server,
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

    assert :ok = perform_job(AppProbe, %{"server_id" => server.id})

    [app] = Apps.list_for_server(server.id)
    assert app.name == "hermes"
    assert app.version == "0.1.0"
  end

  test "fan-out skips servers with no release_command" do
    {:ok, with_cmd} = Fleet.create_server(%{name: "hermes", host: "10.0.0.1"})

    {:ok, _} =
      Fleet.update_monitoring(with_cmd, %{release_command: "/opt/hermes/bin/hermes"})

    {:ok, _without} = Fleet.create_server(%{name: "plain", host: "10.0.0.2"})

    assert :ok = perform_job(AppProbe, %{"all" => true})

    assert_enqueued(worker: AppProbe, args: %{"server_id" => with_cmd.id})
    refute_enqueued(worker: AppProbe, args: %{"server_id" => nil})
  end

  test "probe failure does not crash the worker" do
    {:ok, server} = Fleet.create_server(%{name: "broken", host: "10.0.0.3"})

    {:ok, server} =
      Fleet.update_monitoring(server, %{release_command: "/opt/broken/bin/broken"})

    Stub.plant(server, {:error, :ssh_failed})

    assert :ok = perform_job(AppProbe, %{"server_id" => server.id})
  end
end
