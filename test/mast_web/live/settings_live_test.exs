defmodule MastWeb.SettingsLiveTest do
  use MastWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Mast.{Fleet, Keys}
  alias Mast.Fleet.Projects

  defp pem(name), do: File.read!("test/fixtures/#{name}")

  describe "ssh keys tab" do
    test "renders title and SSH Keys subtab", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings?tab=keys")

      assert html =~ "Manage your Mast configuration"
      assert html =~ "SSH Keys"
      assert html =~ "General"
    end

    test "lists existing keys with a server-usage count", %{conn: conn} do
      {:ok, key} = Keys.create_key(%{name: "deploy_ed25519", body: pem("test_ed25519")})

      {:ok, _server} =
        Fleet.create_server(%{
          name: "uses-key",
          host: "10.0.0.81",
          private_key_id: key.id
        })

      {:ok, _view, html} = live(conn, ~p"/settings?tab=keys")

      assert html =~ "deploy_ed25519"
      assert html =~ "ed25519"
      # One server uses this key.
      assert html =~ "1 server"
    end

    test "inline Add Key form creates a key", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings?tab=keys")

      view |> element("button", "Add Key") |> render_click()

      html =
        view
        |> form("#new-key-form", key: %{name: "new-one", body: pem("test_ed25519")})
        |> render_submit()

      assert html =~ "new-one"
      assert [%{name: "new-one"}] = Keys.list_keys()
    end

    test "delete-key removes a key with no servers", %{conn: conn} do
      {:ok, key} = Keys.create_key(%{name: "unused", body: pem("test_ed25519")})

      {:ok, view, _html} = live(conn, ~p"/settings?tab=keys")

      view
      |> element("button[phx-value-id='#{key.id}'][phx-click='delete-key']")
      |> render_click()

      assert Keys.list_keys() == []
    end
  end

  describe "projects tab" do
    test "renders the Projects subtab in the header", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings?tab=projects")

      assert html =~ "Projects"
      assert html =~ "Manage your Mast configuration"
    end

    test "lists existing projects with a server-usage count", %{conn: conn} do
      {:ok, p} = Projects.create_project(%{name: "blog", color: "emerald"})

      {:ok, _s} =
        Fleet.create_server(%{name: "blog-prod-1", host: "10.0.0.91", project_id: p.id})

      {:ok, _view, html} = live(conn, ~p"/settings?tab=projects")

      assert html =~ "blog"
      assert html =~ "1 server"
    end

    test "inline Add Project form creates a project", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings?tab=projects")

      view |> element("button", "Add Project") |> render_click()

      html =
        view
        |> form("#new-project-form",
          project: %{name: "platform", description: "shared infra", color: "indigo"}
        )
        |> render_submit()

      assert html =~ "platform"
      assert [%{name: "platform", color: "indigo"}] = Projects.list_projects()
    end

    test "rename inline edits a project name and emits project.renamed", %{conn: conn} do
      {:ok, p} = Projects.create_project(%{name: "old-name"})

      {:ok, view, _html} = live(conn, ~p"/settings?tab=projects")

      view
      |> element("button[phx-value-id='#{p.id}'][phx-click='edit-project']")
      |> render_click()

      view
      |> form("#edit-project-form-#{p.id}",
        project: %{name: "new-name", color: "rose"}
      )
      |> render_submit()

      reloaded = Projects.get_project!(p.id)
      assert reloaded.name == "new-name"
      assert reloaded.color == "rose"
    end

    test "delete removes a project", %{conn: conn} do
      {:ok, p} = Projects.create_project(%{name: "to-delete"})

      {:ok, view, _html} = live(conn, ~p"/settings?tab=projects")

      view
      |> element("button[phx-value-id='#{p.id}'][phx-click='delete-project']")
      |> render_click()

      assert Projects.list_projects() == []
    end
  end
end
