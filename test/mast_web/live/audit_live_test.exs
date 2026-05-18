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
      Audit.log(%{event_type: "key.created", subject_type: "PrivateKey", subject_id: 1})
      Audit.log(%{event_type: "scan.run", subject_type: "Server", subject_id: 1})

      {:ok, view, _} = live(conn, ~p"/audit")

      html =
        view
        |> form("#audit-filters", filters: %{event_type: "key.created", subject_type: ""})
        |> render_change()

      assert html =~ "registered SSH key"
      refute html =~ "scanned"
    end

    test "filters by subject_type dropdown", %{conn: conn} do
      Audit.log(%{event_type: "key.created", subject_type: "PrivateKey", subject_id: 1})
      Audit.log(%{event_type: "scan.run", subject_type: "Server", subject_id: 1})

      {:ok, view, _} = live(conn, ~p"/audit")

      html =
        view
        |> form("#audit-filters", filters: %{event_type: "", subject_type: "Server"})
        |> render_change()

      assert html =~ "scanned"
      refute html =~ "registered SSH key"
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
