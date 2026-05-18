defmodule MastWeb.DashboardLiveTest do
  use MastWeb.ConnCase, async: true
  use Oban.Testing, repo: Mast.Repo

  import Phoenix.LiveViewTest

  alias Mast.Fleet

  describe "index" do
    test "shows empty state when no servers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Fleet Overview"
      assert html =~ "No servers yet"
    end

    test "lists servers as cards", %{conn: conn} do
      {:ok, _} = Fleet.create_server(%{name: "alpha", host: "10.0.0.7"})
      {:ok, _} = Fleet.create_server(%{name: "zeta", host: "10.0.0.9"})

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "alpha"
      assert html =~ "zeta"
    end

    test "Add Server button opens the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Two Add Server links exist (header + empty state); both navigate to /servers/new.
      assert view |> has_element?("a[href='/servers/new']", "Add Server")

      {:ok, view, html} = live(conn, ~p"/servers/new")
      assert html =~ "Add a server"
      assert has_element?(view, "#new-server-form")
    end

    test "Add Server modal includes a key dropdown listing registered keys", %{conn: conn} do
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

      view
      |> form("#new-server-form", server: %{name: "web-1", host: "10.0.0.7"})
      |> render_submit()

      assert [%{name: "web-1", host: "10.0.0.7"}] = Fleet.list_servers()
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
