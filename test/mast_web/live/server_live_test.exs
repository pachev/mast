defmodule MastWeb.ServerLiveTest do
  use MastWeb.ConnCase, async: true
  use Oban.Testing, repo: Mast.Repo

  import Phoenix.LiveViewTest

  alias Mast.Fleet
  alias Mast.Workers.ApplyUpdates

  describe "show" do
    test "renders server details", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "alpha", host: "10.0.0.7"})

      {:ok, _view, html} = live(conn, ~p"/servers/#{server}")

      assert html =~ "alpha"
      assert html =~ "10.0.0.7"
      assert html =~ "Apply Updates"
    end

    test "overview shows a Recent Activity card scoped to this server", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "with-activity", host: "10.0.0.50"})
      {:ok, other} = Fleet.create_server(%{name: "noisy", host: "10.0.0.51"})

      {:ok, _} =
        Mast.Audit.log(%{
          event_type: "scan.run",
          subject_type: "Server",
          subject_id: server.id,
          metadata: %{"outcome" => "ok", "updates_available" => 3, "server_name" => server.name}
        })

      {:ok, _} =
        Mast.Audit.log(%{
          event_type: "scan.run",
          subject_type: "Server",
          subject_id: other.id,
          metadata: %{"outcome" => "ok", "updates_available" => 99, "server_name" => other.name}
        })

      {:ok, _view, html} = live(conn, ~p"/servers/#{server}")

      assert html =~ "Recent Activity"
      assert html =~ "3 packages available"
      # Other server's activity must not leak in.
      refute html =~ "99 packages available"
    end

    test "shows scan results when present", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "beta", host: "10.0.0.8"})

      {:ok, _server} =
        Fleet.record_scan(server, %{
          updates_available: 2,
          last_scan: %{
            "total" => 2,
            "updates" => [
              %{"package" => "openssl", "new_version" => "1.0", "current_version" => "0.9"},
              %{"package" => "curl", "new_version" => "2.0", "current_version" => "1.9"}
            ]
          }
        })

      {:ok, _view, html} = live(conn, ~p"/servers/#{server}?tab=updates")

      assert html =~ "openssl"
      assert html =~ "curl"
    end

    test "Apply All button enqueues an ApplyUpdates job", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "gamma", host: "10.0.0.9"})
      {:ok, server} = Fleet.update_server_meta(server, %{package_manager: "apt"})

      {:ok, _} =
        Fleet.record_scan(server, %{
          updates_available: 1,
          last_scan: %{"total" => 1, "updates" => [%{"package" => "curl"}]}
        })

      {:ok, view, _html} = live(conn, ~p"/servers/#{server}")

      view |> element("button", "Apply Updates") |> render_click()

      assert_enqueued(
        worker: ApplyUpdates,
        args: %{"server_id" => server.id, "scope" => "all"}
      )
    end

    test "clicking Scan updates shows a scanning indicator", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "scan-target", host: "10.0.0.11"})
      {:ok, server} = Fleet.update_server_meta(server, %{package_manager: "apt"})

      {:ok, view, _html} = live(conn, ~p"/servers/#{server}")

      refute render(view) =~ "Scanning…"

      html = view |> element("button", "Scan Updates") |> render_click()
      assert html =~ "Scanning…"

      # When the scan completes, the indicator clears.
      Phoenix.PubSub.broadcast(
        Mast.PubSub,
        "servers",
        {:server_updated, %{server | updates_available: 0, last_scan_at: DateTime.utc_now()}}
      )

      refute render(view) =~ "Scanning…"
    end

    test "shows distinct copy for never-scanned vs zero-updates", %{conn: conn} do
      {:ok, never} = Fleet.create_server(%{name: "fresh", host: "10.0.0.12"})
      {:ok, _view, html} = live(conn, ~p"/servers/#{never}?tab=updates")
      assert html =~ "Not scanned yet"

      {:ok, zero} = Fleet.create_server(%{name: "clean", host: "10.0.0.13"})

      {:ok, _zero} =
        Fleet.record_scan(zero, %{
          updates_available: 0,
          last_scan: %{"total" => 0, "updates" => []}
        })

      {:ok, _view2, html2} = live(conn, ~p"/servers/#{zero}?tab=updates")
      assert html2 =~ "All up to date"
      refute html2 =~ "Not scanned yet"
    end

    test "broadcasts scan failure so the UI doesn't hang", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "broken", host: "10.0.0.14"})
      {:ok, server} = Fleet.update_server_meta(server, %{package_manager: "apt"})

      {:ok, view, _} = live(conn, ~p"/servers/#{server}")

      view |> element("button", "Scan Updates") |> render_click()
      assert render(view) =~ "Scanning…"

      # Simulate the worker reporting an error.
      Phoenix.PubSub.broadcast(
        Mast.PubSub,
        "servers",
        {:scan_failed, server.id, "sudo: a password is required"}
      )

      html = render(view)
      refute html =~ "Scanning…"
      assert html =~ "sudo: a password is required"
    end

    test "updates tab paginates package list at 10/page", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "many", host: "10.0.0.41"})

      updates =
        for i <- 1..25 do
          %{
            "package" => "pkg#{String.pad_leading(Integer.to_string(i), 2, "0")}",
            "current_version" => "1.0",
            "new_version" => "1.1"
          }
        end

      {:ok, _} =
        Fleet.record_scan(server, %{
          updates_available: 25,
          last_scan: %{"total" => 25, "updates" => updates}
        })

      {:ok, view, html} = live(conn, ~p"/servers/#{server}?tab=updates")

      # Page 1 shows pkg01..pkg10, not pkg11+.
      assert html =~ "pkg01"
      assert html =~ "pkg10"
      refute html =~ "pkg11"
      assert html =~ "Showing 1"
      assert html =~ "of 25"

      # Jump to page 2.
      html = view |> render_click("goto-page", %{"page" => "2"})
      assert html =~ "pkg11"
      assert html =~ "pkg20"
      refute html =~ "pkg01"
    end

    test "updates tab filters by package name via search input", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "filtered", host: "10.0.0.42"})

      {:ok, _} =
        Fleet.record_scan(server, %{
          updates_available: 3,
          last_scan: %{
            "total" => 3,
            "updates" => [
              %{"package" => "openssl", "current_version" => "1", "new_version" => "2"},
              %{"package" => "curl", "current_version" => "1", "new_version" => "2"},
              %{"package" => "wget", "current_version" => "1", "new_version" => "2"}
            ]
          }
        })

      {:ok, view, _html} = live(conn, ~p"/servers/#{server}?tab=updates")

      html = view |> form("#updates-filter", %{q: "curl"}) |> render_change()
      assert html =~ "curl"
      refute html =~ "openssl"
      refute html =~ "wget"
    end

    test "settings tab shows a Danger Zone with a Remove button", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "zulu", host: "10.0.0.99"})

      {:ok, _view, html} = live(conn, ~p"/servers/#{server}?tab=settings")

      assert html =~ "Danger zone"
      assert html =~ "Remove Server"
    end

    test "remove flow requires typing the server name, then deletes + redirects",
         %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "doomed", host: "10.0.0.77"})

      {:ok, view, _html} = live(conn, ~p"/servers/#{server}?tab=settings")

      # Open the confirm modal.
      html = view |> element("button", "Remove Server") |> render_click()
      assert html =~ "Type the server name to confirm"

      # Wrong text -> button disabled, server still here.
      _ = view |> form("#confirm-delete-form", %{confirm: %{name: "nope"}}) |> render_change()
      assert Mast.Fleet.get_server!(server.id)

      # Cancel keeps server intact and closes modal.
      html = view |> element("button", "Cancel") |> render_click()
      refute html =~ "Type the server name to confirm"
      assert Mast.Fleet.get_server!(server.id)

      # Reopen, type correct name, submit -> redirect to /.
      _ = view |> element("button", "Remove Server") |> render_click()
      _ = view |> form("#confirm-delete-form", %{confirm: %{name: "doomed"}}) |> render_change()

      assert {:error, {:live_redirect, %{to: "/"}}} =
               view |> form("#confirm-delete-form") |> render_submit()

      assert_raise Ecto.NoResultsError, fn -> Mast.Fleet.get_server!(server.id) end
    end

    test "overview renders charts with default range 1h", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "charted", host: "10.0.0.80"})

      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      for i <- 0..4 do
        at = DateTime.add(now, -i * 60, :second)

        {:ok, _} =
          Fleet.record_sample(server, %{
            bucket: "1m",
            recorded_at: at,
            stats: %{"cpu" => i * 10.0, "memory" => 50.0}
          })
      end

      {:ok, _view, html} = live(conn, ~p"/servers/#{server}")

      assert html =~ "CPU over time"
      assert html =~ ~s(<canvas)
      assert html =~ "MetricChart"
      # Default range is 1h.
      assert html =~ ~s(value="1h" selected)
    end

    test "overview renders empty-state when there are no samples", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "nochart", host: "10.0.0.81"})

      {:ok, _view, html} = live(conn, ~p"/servers/#{server}")

      assert html =~ "Waiting for more samples"
    end

    test "changing range to 7d re-queries with 120m bucket", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "ranged", host: "10.0.0.82"})

      # Need at least 2 points for the chart to render a canvas (one point
      # collapses the x-axis); see Charts.line_chart/1.
      for offset_days <- [3, 2] do
        at =
          DateTime.add(DateTime.utc_now(), -offset_days * 86_400, :second)
          |> DateTime.truncate(:microsecond)

        {:ok, _} =
          Fleet.record_sample(server, %{
            bucket: "120m",
            recorded_at: at,
            stats: %{"cpu" => 42.0}
          })
      end

      {:ok, view, _html} = live(conn, ~p"/servers/#{server}")

      html = view |> element("#range-form") |> render_change(%{"range" => "7d"})
      assert html =~ ~s(value="7d" selected)
      assert html =~ ~s(<canvas)
    end

    test "dashboard removes the row on :server_deleted broadcast", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "ghost", host: "10.0.0.66"})

      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ "ghost"

      {:ok, _} = Mast.Fleet.delete_server(server)

      # delete_server should broadcast :server_deleted on the "servers" topic.
      html = render(view)
      refute html =~ "ghost"
    end
  end

  describe "header — project badge" do
    alias Mast.Fleet.Projects

    test "renders the Project badge when the server belongs to a project", %{conn: conn} do
      {:ok, p} = Projects.create_project(%{name: "blog", color: "emerald"})

      {:ok, server} =
        Fleet.create_server(%{name: "blog-prod-1", host: "10.0.0.80", project_id: p.id})

      {:ok, _view, html} = live(conn, ~p"/servers/#{server}")

      assert html =~ "Project: blog"
      assert html =~ "blog"
    end

    test "omits the Project badge when the server has no project", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "lone", host: "10.0.0.81"})

      {:ok, _view, html} = live(conn, ~p"/servers/#{server}")

      refute html =~ "Project: "
    end
  end

  describe "settings tab — project assignment" do
    alias Mast.Fleet.Projects

    test "shows a Project dropdown on the settings tab", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "needs-proj", host: "10.0.0.70"})
      {:ok, _p} = Projects.create_project(%{name: "blog"})

      {:ok, _view, html} = live(conn, ~p"/servers/#{server}?tab=settings")

      assert html =~ "Project"
      assert html =~ "blog"
    end

    test "assigning a project via the form emits an audit event", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "to-assign", host: "10.0.0.71"})
      {:ok, p} = Projects.create_project(%{name: "infra"})

      {:ok, view, _html} = live(conn, ~p"/servers/#{server}?tab=settings")

      view
      |> form("#server-project-form", server: %{project_id: p.id})
      |> render_submit()

      reloaded = Fleet.get_server!(server.id)
      assert reloaded.project_id == p.id

      types =
        "Server"
        |> Mast.Audit.list_for_subject(server.id)
        |> Enum.map(& &1.event_type)

      assert "server.project_assigned" in types
    end

    test "unassigning by selecting the blank option clears project_id", %{conn: conn} do
      {:ok, p} = Projects.create_project(%{name: "leaving"})

      {:ok, server} =
        Fleet.create_server(%{name: "to-unassign", host: "10.0.0.72", project_id: p.id})

      {:ok, view, _html} = live(conn, ~p"/servers/#{server}?tab=settings")

      view
      |> form("#server-project-form", server: %{project_id: ""})
      |> render_submit()

      assert Fleet.get_server!(server.id).project_id == nil
    end
  end
end
