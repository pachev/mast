defmodule MastWeb.DashboardLiveTest do
  use MastWeb.ConnCase, async: true
  use Oban.Testing, repo: Mast.Repo

  import Phoenix.LiveViewTest

  alias Mast.Fleet
  alias Mast.Workers.ConnectionCheck

  describe "index" do
    test "shows empty state when no servers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "All Systems"
      assert html =~ "No systems yet"
    end

    test "lists servers in a table", %{conn: conn} do
      {:ok, _} = Fleet.create_server(%{name: "alpha", host: "10.0.0.7"})
      {:ok, _} = Fleet.create_server(%{name: "zeta", host: "10.0.0.9"})

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "alpha"
      assert html =~ "zeta"
      assert html =~ "10.0.0.7"
    end

    test "Add System button opens the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("a", "Add System") |> render_click()
      assert_patched(view, ~p"/servers/new")
      assert render(view) =~ "Add a system"
    end

    test "Add System modal includes a key dropdown listing registered keys", %{conn: conn} do
      {:ok, _} =
        Mast.Keys.create_key(%{
          name: "elpajo prod",
          body: File.read!("test/fixtures/test_ed25519")
        })

      {:ok, view, _} = live(conn, ~p"/servers/new")
      html = render(view)

      assert html =~ "Private key"
      assert html =~ "elpajo prod"
    end

    test "submits a new server with private_key_id", %{conn: conn} do
      {:ok, key} =
        Mast.Keys.create_key(%{
          name: "elpajo prod",
          body: File.read!("test/fixtures/test_ed25519")
        })

      {:ok, view, _} = live(conn, ~p"/servers/new")

      view
      |> form("#new-server-form",
        server: %{
          name: "with-key",
          host: "10.0.0.7",
          private_key_id: Integer.to_string(key.id)
        }
      )
      |> render_submit()

      [server] = Mast.Fleet.list_servers()
      assert server.name == "with-key"
      assert server.private_key_id == key.id
    end

    test "submitting the new-server form creates a server", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/servers/new")

      html =
        view
        |> form("#new-server-form", server: %{name: "web-1", host: "10.0.0.7"})
        |> render_submit()

      assert html =~ "web-1"
      assert html =~ "10.0.0.7"
      assert [%{name: "web-1"}] = Fleet.list_servers()
    end

    test "clicking 'Check' enqueues a ConnectionCheck job for that server", %{conn: conn} do
      {:ok, server} = Fleet.create_server(%{name: "alpha", host: "10.0.0.7"})

      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element(~s|button[phx-click="check"][phx-value-id="#{server.id}"]|)
      |> render_click()

      assert_enqueued(worker: ConnectionCheck, args: %{"server_id" => server.id})
    end

    test "form shows validation errors on bad submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/servers/new")

      html =
        view
        |> form("#new-server-form", server: %{name: "", host: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end
end
