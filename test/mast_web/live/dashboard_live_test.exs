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
          private_key_id: key.id
        }
      )
      |> render_submit()

      [server] = Mast.Fleet.list_servers()
      assert server.name == "with-key"
      assert server.private_key_id == key.id
    end

    test "inline 'Add new key' expands a form inside the modal", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/servers/new")

      refute has_element?(view, "#new-key-form")

      view |> element("[phx-click=toggle_new_key]") |> render_click()

      assert has_element?(view, "#new-key-form")
      assert has_element?(view, "#new-key-form textarea[name='key[body]']")
      assert has_element?(view, "#new-key-form input[name='key[name]']")
    end

    test "saving an inline key creates it and selects it in the server form", %{conn: conn} do
      pem = File.read!("test/fixtures/test_ed25519")
      {:ok, view, _} = live(conn, ~p"/servers/new")

      view |> element("[phx-click=toggle_new_key]") |> render_click()

      html =
        view
        |> form("#new-key-form", key: %{name: "inline key", body: pem})
        |> render_submit()

      # Form collapses on success, dropdown now lists the key, and it's selected.
      refute has_element?(view, "#new-key-form")
      assert html =~ "inline key"

      assert [%{name: "inline key"}] = Mast.Keys.list_keys()
      [key] = Mast.Keys.list_keys()

      assert has_element?(
               view,
               "select[name='server[private_key_id]'] option[selected][value='#{key.id}']"
             )
    end

    test "inline key form shows error for passphrase'd PEM without closing modal", %{conn: conn} do
      pem = File.read!("test/fixtures/test_with_passphrase")
      {:ok, view, _} = live(conn, ~p"/servers/new")

      view |> element("[phx-click=toggle_new_key]") |> render_click()

      html =
        view
        |> form("#new-key-form", key: %{name: "bad", body: pem})
        |> render_submit()

      assert html =~ "encrypted private keys are not supported"
      assert has_element?(view, "#new-server-form")
      assert has_element?(view, "#new-key-form")
      assert Mast.Keys.list_keys() == []
    end

    test "inline key form shows duplicate-fingerprint error", %{conn: conn} do
      pem = File.read!("test/fixtures/test_ed25519")
      {:ok, _} = Mast.Keys.create_key(%{name: "already here", body: pem})

      {:ok, view, _} = live(conn, ~p"/servers/new")
      view |> element("[phx-click=toggle_new_key]") |> render_click()

      html =
        view
        |> form("#new-key-form", key: %{name: "dup", body: pem})
        |> render_submit()

      assert html =~ "this key is already registered"
      assert has_element?(view, "#new-key-form")
    end

    test "submitting the new-server form creates a server", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/servers/new")

      view
      |> form("#new-server-form", server: %{name: "web-1", host: "10.0.0.7"})
      |> render_submit()

      assert [%{name: "web-1", host: "10.0.0.7"}] = Fleet.list_servers()
    end

    test "creating a server immediately enqueues a ConnectionCheck", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/servers/new")

      view
      |> form("#new-server-form", server: %{name: "hermes", host: "10.0.0.42"})
      |> render_submit()

      [server] = Fleet.list_servers()

      assert_enqueued(
        worker: Mast.Workers.ConnectionCheck,
        args: %{"server_id" => server.id}
      )
    end

    test "form shows validation errors on bad submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/servers/new")

      html =
        view
        |> form("#new-server-form", server: %{name: "", host: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "ignores unrelated PubSub broadcasts on the servers topic", %{conn: conn} do
      # The dashboard subscribes to the "servers" topic, which also carries
      # scan/probe events targeting the per-server LiveView. The dashboard
      # should not crash on messages it doesn't care about.
      {:ok, view, _html} = live(conn, ~p"/")

      for msg <- [
            {:scan_failed, 1, "boom"},
            {:apps_updated, 1},
            {:apps_probe_failed, 1, :nxdomain},
            {:run_event, "abc", {:exit, 0}}
          ] do
        Phoenix.PubSub.broadcast(Mast.PubSub, "servers", msg)
      end

      assert render(view) =~ "Fleet Overview"
    end
  end

  describe "fleet grouping by project" do
    alias Mast.Fleet.Projects

    test "renders a collapsible group header for each project with members", %{conn: conn} do
      {:ok, blog} = Projects.create_project(%{name: "blog", color: "emerald"})

      {:ok, _} =
        Fleet.create_server(%{name: "blog-prod-1", host: "10.0.1.1", project_id: blog.id})

      {:ok, _} =
        Fleet.create_server(%{name: "blog-prod-2", host: "10.0.1.2", project_id: blog.id})

      {:ok, _} = Fleet.create_server(%{name: "lone", host: "10.0.1.3"})

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "blog"
      # Group count rendered inside the header.
      assert html =~ "2 servers"
      # The ungrouped server still shows.
      assert html =~ "lone"
      # No "Unassigned" pseudo-group.
      refute html =~ "Unassigned"
    end

    test "clicking a group header toggles its expanded state", %{conn: conn} do
      {:ok, p} = Projects.create_project(%{name: "infra"})
      {:ok, _} = Fleet.create_server(%{name: "infra-1", host: "10.0.2.1", project_id: p.id})

      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ "infra-1"

      view
      |> element("[phx-click='toggle-project-group'][phx-value-id='#{p.id}']")
      |> render_click()

      html = render(view)
      # Card is gone from DOM when collapsed.
      refute html =~ "infra-1"
    end
  end

  describe "Add Server modal — projects" do
    alias Mast.Fleet.Projects

    test "shows a Project dropdown listing registered projects", %{conn: conn} do
      {:ok, _p} = Projects.create_project(%{name: "blog"})

      {:ok, view, _} = live(conn, ~p"/servers/new")
      html = render(view)

      assert html =~ "Project"
      assert html =~ "blog"
    end

    test "submits a new server with project_id", %{conn: conn} do
      {:ok, p} = Projects.create_project(%{name: "platform"})

      {:ok, view, _} = live(conn, ~p"/servers/new")

      view
      |> form("#new-server-form",
        server: %{name: "with-project", host: "10.0.0.30", project_id: p.id}
      )
      |> render_submit()

      [server] = Mast.Fleet.list_servers()
      assert server.name == "with-project"
      assert server.project_id == p.id
    end

    test "inline 'Add new project' expands a form inside the modal", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/servers/new")

      refute has_element?(view, "#new-project-form")

      view |> element("[phx-click=toggle_new_project]") |> render_click()

      assert has_element?(view, "#new-project-form")
    end

    test "inline project creation selects the new project on the server form", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/servers/new")

      view |> element("[phx-click=toggle_new_project]") |> render_click()

      view
      |> form("#new-project-form", project: %{name: "infra", color: "indigo"})
      |> render_submit()

      [project] = Projects.list_projects()
      html = render(view)

      assert html =~ "infra"
      # The new project is the selected option on the server form.
      selected_option =
        Regex.run(~r/<option[^>]*selected[^>]*value="([^"]+)"[^>]*>infra/, html) ||
          Regex.run(~r/<option[^>]*value="([^"]+)"[^>]*selected[^>]*>infra/, html)

      assert selected_option, "Expected the 'infra' option to be selected. Got: #{html}"
      assert Enum.at(selected_option, 1) == project.id
    end
  end
end
