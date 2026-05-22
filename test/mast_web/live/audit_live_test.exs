defmodule MastWeb.AuditLiveTest do
  use MastWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Mast.Audit
  alias Mast.Fleet
  alias Mast.Keys

  describe "/audit" do
    test "shows an empty state when nothing has happened", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/audit")
      assert html =~ "Audit"
      assert html =~ "0 events"
    end

    test "renders real audit events from the DB, newest first", %{conn: conn} do
      pem = File.read!("test/fixtures/test_ed25519")
      {:ok, _key} = Keys.create_key(%{name: "hermes-key", body: pem})
      {:ok, _server} = Fleet.create_server(%{name: "hermes", host: "10.0.0.42"})

      {:ok, _view, html} = live(conn, ~p"/audit")

      # Both real events show up, with real names — no "web-prod-1" mock data.
      assert html =~ "hermes"
      assert html =~ "hermes-key"
      refute html =~ "web-prod-1"
      refute html =~ "12 packages available"
    end

    test "filters by event_type dropdown", %{conn: conn} do
      sid = Ecto.UUID.generate()
      Audit.log(%{event_type: "key.created", subject_type: "PrivateKey", subject_id: sid})
      Audit.log(%{event_type: "scan.run", subject_type: "Server", subject_id: sid})

      {:ok, view, _} = live(conn, ~p"/audit")

      html =
        view
        |> form("#audit-filters", filters: %{event_type: "key.created", subject_type: ""})
        |> render_change()

      assert html =~ "registered SSH key"
      refute html =~ "scanned"
    end

    test "filters by subject_type dropdown", %{conn: conn} do
      sid = Ecto.UUID.generate()
      Audit.log(%{event_type: "key.created", subject_type: "PrivateKey", subject_id: sid})
      Audit.log(%{event_type: "scan.run", subject_type: "Server", subject_id: sid})

      {:ok, view, _} = live(conn, ~p"/audit")

      html =
        view
        |> form("#audit-filters", filters: %{event_type: "", subject_type: "Server"})
        |> render_change()

      assert html =~ "scanned"
      refute html =~ "registered SSH key"
    end

    test "load_more appends the next cursor page", %{conn: conn} do
      for n <- 1..60, do: Audit.log(%{event_type: "test.e#{n}"})

      {:ok, view, html} = live(conn, ~p"/audit")

      # First page is 50, label switches to "newest 50" because more pages exist.
      assert html =~ "newest 50"
      assert html =~ "Load more"
      assert html =~ "test.e60"
      refute html =~ "test.e10"

      html = render_click(view, "load_more")

      # All 60 events visible, no more "Load more" button.
      assert html =~ "test.e10"
      assert html =~ "test.e1<"
      refute html =~ "Load more"
      assert html =~ "60 events"
    end

    test "search query pushes to the URL and filters server-side", %{conn: conn} do
      Audit.log(%{event_type: "key.created"})
      Audit.log(%{event_type: "scan.run"})

      {:ok, view, _} = live(conn, ~p"/audit")

      html =
        view
        |> form("form[phx-change=filter]", %{"q" => "scan"})
        |> render_change()

      assert html =~ "scanned"
      refute html =~ "registered SSH key"
      assert_patched(view, ~p"/audit?q=scan")
    end

    test "page_size query string overrides the default", %{conn: conn} do
      for n <- 1..5, do: Audit.log(%{event_type: "test.e#{n}"})

      {:ok, _view, html} = live(conn, ~p"/audit?page_size=2")
      assert html =~ "newest 2"
      assert html =~ "Load more"
    end

    test "renders a scan.run event with the real package count", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "hermes", host: "10.0.0.42"})

      {:ok, _} =
        Audit.log(%{
          event_type: "scan.run",
          subject_type: "Server",
          subject_id: server.id,
          metadata: %{"outcome" => "ok", "updates_available" => 3, "server_name" => "hermes"}
        })

      {:ok, _view, html} = live(conn, ~p"/audit")
      assert html =~ "hermes"
      assert html =~ "3"
      refute html =~ "12 packages"
    end
  end
end
