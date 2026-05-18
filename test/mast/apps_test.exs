defmodule Mast.AppsTest do
  use Mast.DataCase, async: true

  alias Mast.{Apps, Fleet}

  setup do
    {:ok, server} = Fleet.create_server(%{name: "hermes", host: "10.0.0.1"})
    {:ok, server: server}
  end

  describe "upsert_from_probe/2" do
    test "inserts brand new apps", %{server: server} do
      observations = [
        %{
          name: "mast_web",
          node_name: "mast@host",
          version: "0.4.0",
          status: "running",
          memory_mb: 12.4,
          processes: 521,
          uptime_seconds: 1200
        }
      ]

      {:ok, [app]} = Apps.upsert_from_probe(server, observations)
      assert app.name == "mast_web"
      assert app.version == "0.4.0"
      assert app.status == "running"
      assert app.last_seen_at
    end

    test "updates known apps", %{server: server} do
      {:ok, _} =
        Apps.upsert_from_probe(server, [
          %{name: "hermes", node_name: "h@h", status: "running", version: "0.1.0"}
        ])

      {:ok, _} =
        Apps.upsert_from_probe(server, [
          %{name: "hermes", node_name: "h@h", status: "running", version: "0.2.0"}
        ])

      [app] = Apps.list_for_server(server.id)
      assert app.version == "0.2.0"
    end

    test "marks missing apps unreachable", %{server: server} do
      {:ok, _} =
        Apps.upsert_from_probe(server, [
          %{name: "hermes", node_name: "h@h", status: "running"},
          %{name: "old_app", node_name: "h@h", status: "running"}
        ])

      {:ok, _} =
        Apps.upsert_from_probe(server, [
          %{name: "hermes", node_name: "h@h", status: "running"}
        ])

      apps = Apps.list_for_server(server.id) |> Map.new(&{&1.name, &1})
      assert apps["hermes"].status == "running"
      assert apps["old_app"].status == "unreachable"
    end
  end
end
