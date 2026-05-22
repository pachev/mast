defmodule MastWeb.ApplicationLiveTest do
  use MastWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mast.{Apps, Fleet}
  alias Mast.Apps.Probe.Stub

  setup do
    Stub.reset()
    {:ok, server} = Fleet.create_server(%{name: "hermes", host: "10.0.0.1"})

    {:ok, release} =
      Fleet.create_release(%{
        server_id: server.id,
        release_command: "/opt/hermes/bin/hermes"
      })

    {:ok, [app]} =
      Apps.upsert_from_probe(release, [
        %{
          name: "hermes",
          node_name: "hermes@host",
          version: "0.1.0",
          status: "running",
          memory_mb: 106.0,
          processes: 536,
          msg_queue: 0,
          otp_release: "28",
          uptime_seconds: 2100
        }
      ])

    {:ok, server: server, release: release, app: app}
  end

  test "renders scalar stats + fallback banner when observer_backend is unavailable",
       %{conn: conn, server: server, release: release, app: app} do
    Stub.plant_detail(release, app.name, {:error, :observer_backend_unavailable})

    {:ok, _view, html} = live(conn, ~p"/servers/#{server.id}/releases/hermes/apps/#{app.name}")

    # Existing scalar stats still render.
    assert html =~ "106.0 MB"

    # Info banner is visible and points at runtime_tools.
    assert html =~ ":runtime_tools"
    assert html =~ "Detailed metrics unavailable"

    # New observer sections are NOT rendered when detail is unavailable.
    refute html =~ "System snapshot"
    refute html =~ "Supervision tree"
    refute html =~ "Top by memory"
  end

  test "renders observer sections when detail probe succeeds",
       %{conn: conn, server: server, release: release, app: app} do
    Stub.plant_detail(release, app.name, {
      :ok,
      %{
        sys_info: %{
          scheduler_utilization: 12.5,
          atom_count: 18_321,
          port_count: 42,
          process_count: 536,
          ets_count: 91,
          memory_by_category: %{
            processes: 60_000_000,
            atom: 1_200_000,
            binary: 4_000_000,
            ets: 800_000,
            code: 12_000_000,
            total: 111_000_000
          }
        },
        sup_tree: [
          %{
            name: "Hermes.Supervisor",
            pid: "#PID<0.123.0>",
            type: "supervisor",
            depth: 0,
            children: [
              %{
                name: "Hermes.Repo",
                pid: "#PID<0.124.0>",
                type: "worker",
                depth: 1,
                children: []
              }
            ]
          }
        ],
        top_memory: [
          %{
            name: "Hermes.Repo",
            pid: "#PID<0.124.0>",
            memory: 1_048_576,
            reductions: 42_000,
            msg_queue_len: 0
          }
        ],
        top_msgq: [
          %{
            name: "Hermes.Worker",
            pid: "#PID<0.200.0>",
            memory: 4096,
            reductions: 12,
            msg_queue_len: 7
          }
        ]
      }
    })

    {:ok, _view, html} = live(conn, ~p"/servers/#{server.id}/releases/hermes/apps/#{app.name}")

    assert html =~ "System snapshot"
    assert html =~ "Supervision tree"
    assert html =~ "Top by memory"
    assert html =~ "Top by message queue"
    assert html =~ "Hermes.Supervisor"
    assert html =~ "Hermes.Repo"
    assert html =~ "Hermes.Worker"
    refute html =~ "Detailed metrics unavailable"
  end
end
