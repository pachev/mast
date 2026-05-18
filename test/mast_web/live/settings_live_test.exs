defmodule MastWeb.SettingsLiveTest do
  use MastWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Mast.{Fleet, Keys}

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
end
