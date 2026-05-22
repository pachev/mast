defmodule MastWeb.ReleaseLiveTest do
  use MastWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mast.Fleet

  setup do
    {:ok, server} = Fleet.create_server(%{name: "hermes", host: "10.0.0.1"})

    {:ok, release} =
      Fleet.create_release(%{
        server_id: server.id,
        release_command: "/opt/hermes/bin/hermes"
      })

    {:ok, server: server, release: release}
  end

  test "renders Overview tab by default", %{conn: conn, server: server} do
    {:ok, _view, html} = live(conn, ~p"/servers/#{server.id}/releases/hermes")

    assert html =~ "No applications observed yet"
    assert html =~ "/opt/hermes/bin/hermes"
  end

  test "Settings tab renders form", %{conn: conn, server: server} do
    {:ok, _view, html} =
      live(conn, ~p"/servers/#{server.id}/releases/hermes?tab=settings")

    assert html =~ "Release Command"
    assert html =~ "Log Source"
    assert html =~ "Log Target"
  end

  test "Logs tab shows empty state when log_source is none",
       %{conn: conn, server: server} do
    {:ok, _view, html} = live(conn, ~p"/servers/#{server.id}/releases/hermes?tab=logs")

    assert html =~ "No Log Source configured"
  end

  test "redirects when release is missing", %{conn: conn, server: server} do
    assert {:error, {:live_redirect, %{to: path}}} =
             live(conn, ~p"/servers/#{server.id}/releases/missing")

    assert path == ~p"/servers/#{server.id}"
  end

  test "settings form saves log source", %{conn: conn, server: server, release: release} do
    {:ok, view, _html} =
      live(conn, ~p"/servers/#{server.id}/releases/hermes?tab=settings")

    view
    |> form("form", %{
      "release" => %{
        "name" => "",
        "release_command" => release.release_command,
        "log_source" => "systemd",
        "log_target" => "hermes.service"
      }
    })
    |> render_submit()

    reloaded = Fleet.get_release!(release.id)
    assert reloaded.log_source == "systemd"
    assert reloaded.log_target == "hermes.service"
  end
end
