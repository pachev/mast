defmodule Mast.AppsTest do
  use Mast.DataCase, async: true

  alias Mast.{Apps, Fleet}

  setup do
    {:ok, server} = Fleet.create_server(%{name: "hermes", host: "10.0.0.1"})

    {:ok, release} =
      Fleet.create_release(%{
        server_id: server.id,
        release_command: "/opt/hermes/bin/hermes"
      })

    {:ok, server: server, release: release}
  end

  describe "upsert_from_probe/2" do
    test "inserts brand new apps", %{release: release} do
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

      {:ok, [app]} = Apps.upsert_from_probe(release, observations)
      assert app.name == "mast_web"
      assert app.version == "0.4.0"
      assert app.status == "running"
      assert app.release_id == release.id
      assert app.last_seen_at
    end

    test "updates known apps", %{release: release} do
      {:ok, _} =
        Apps.upsert_from_probe(release, [
          %{name: "hermes", node_name: "h@h", status: "running", version: "0.1.0"}
        ])

      {:ok, _} =
        Apps.upsert_from_probe(release, [
          %{name: "hermes", node_name: "h@h", status: "running", version: "0.2.0"}
        ])

      [app] = Apps.list_for_release(release)
      assert app.version == "0.2.0"
    end

    test "marks missing apps unreachable", %{release: release} do
      {:ok, _} =
        Apps.upsert_from_probe(release, [
          %{name: "hermes", node_name: "h@h", status: "running"},
          %{name: "old_app", node_name: "h@h", status: "running"}
        ])

      {:ok, _} =
        Apps.upsert_from_probe(release, [
          %{name: "hermes", node_name: "h@h", status: "running"}
        ])

      apps = Apps.list_for_release(release) |> Map.new(&{&1.name, &1})
      assert apps["hermes"].status == "running"
      assert apps["old_app"].status == "unreachable"
    end

    test "two Releases on the same Server own separate app rows for shared names",
         %{server: server, release: hermes_release} do
      {:ok, toy_release} =
        Fleet.create_release(%{
          server_id: server.id,
          name: "toy",
          release_command: "/opt/toy/bin/toy"
        })

      {:ok, _} =
        Apps.upsert_from_probe(hermes_release, [
          %{name: "logger", node_name: "h@h", status: "running", version: "1.0.0"}
        ])

      {:ok, _} =
        Apps.upsert_from_probe(toy_release, [
          %{name: "logger", node_name: "t@h", status: "running", version: "1.0.5"}
        ])

      [hermes_logger] = Apps.list_for_release(hermes_release)
      [toy_logger] = Apps.list_for_release(toy_release)

      assert hermes_logger.version == "1.0.0"
      assert toy_logger.version == "1.0.5"
      refute hermes_logger.id == toy_logger.id
    end
  end
end
