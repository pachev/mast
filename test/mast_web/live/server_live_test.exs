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
      assert html =~ "Apply All Updates"
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

      {:ok, _view, html} = live(conn, ~p"/servers/#{server}")

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

      view |> element("button", "Apply All Updates") |> render_click()

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

      html = view |> element("button", "Scan updates") |> render_click()
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
      {:ok, _view, html} = live(conn, ~p"/servers/#{never}")
      assert html =~ "Not scanned yet"

      {:ok, zero} = Fleet.create_server(%{name: "clean", host: "10.0.0.13"})

      {:ok, _zero} =
        Fleet.record_scan(zero, %{
          updates_available: 0,
          last_scan: %{"total" => 0, "updates" => []}
        })

      {:ok, _view2, html2} = live(conn, ~p"/servers/#{zero}")
      assert html2 =~ "All up to date"
      refute html2 =~ "Not scanned yet"
    end

    test "broadcasts scan failure so the UI doesn't hang", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "broken", host: "10.0.0.14"})
      {:ok, server} = Fleet.update_server_meta(server, %{package_manager: "apt"})

      {:ok, view, _} = live(conn, ~p"/servers/#{server}")

      view |> element("button", "Scan updates") |> render_click()
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

    test "live log pane shows streamed events", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "delta", host: "10.0.0.10"})

      {:ok, view, _html} = live(conn, ~p"/servers/#{server}")

      # Grab the run_id the LV created on mount by digging into assigns.
      run_id = :sys.get_state(view.pid).socket.assigns.run_id

      Phoenix.PubSub.broadcast(
        Mast.PubSub,
        "runs:#{run_id}",
        {:run_event, run_id, {:line, :stdout, "hello from upgrade\n"}}
      )

      html = render(view)
      assert html =~ "hello from upgrade"
    end
  end
end
