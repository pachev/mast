defmodule Mast.Fleet.ReleaseTest do
  use Mast.DataCase, async: true

  alias Mast.Fleet.Release
  alias Mast.Fleet.Server

  defp server_fixture(attrs \\ %{}) do
    defaults = %{name: "srv-#{System.unique_integer([:positive])}", host: "10.0.0.1"}

    {:ok, server} =
      %Server{}
      |> Server.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    server
  end

  describe "changeset/2" do
    test "requires server_id" do
      cs = Release.changeset(%Release{}, %{})
      assert {"can't be blank", _} = cs.errors[:server_id]
    end

    test "accepts a release_command and no name" do
      s = server_fixture()

      cs =
        Release.changeset(%Release{}, %{
          server_id: s.id,
          release_command: "/opt/app/bin/app"
        })

      assert cs.valid?
    end

    test "accepts no release_command (logs-only Release)" do
      s = server_fixture()

      cs =
        Release.changeset(%Release{}, %{
          server_id: s.id,
          log_source: "file",
          log_target: "/var/log/app.log"
        })

      assert cs.valid?
    end

    test "rejects release_command that is not absolute" do
      s = server_fixture()

      cs =
        Release.changeset(%Release{}, %{
          server_id: s.id,
          release_command: "bin/app"
        })

      refute cs.valid?
      assert {"must be an absolute path", _} = cs.errors[:release_command]
    end

    test "accepts a valid name" do
      s = server_fixture()

      cs =
        Release.changeset(%Release{}, %{
          server_id: s.id,
          name: "web-1",
          release_command: "/opt/app/bin/app"
        })

      assert cs.valid?
    end

    test "rejects names that contain invalid characters" do
      s = server_fixture()

      for bad <- ["Web", "web_one!", "web one", "-web", "_web"] do
        cs =
          Release.changeset(%Release{}, %{
            server_id: s.id,
            name: bad,
            release_command: "/opt/app/bin/app"
          })

        refute cs.valid?, "expected #{inspect(bad)} to be rejected"
      end
    end

    test "rejects unknown log_source" do
      s = server_fixture()

      cs =
        Release.changeset(%Release{}, %{
          server_id: s.id,
          release_command: "/opt/app/bin/app",
          log_source: "syslog"
        })

      refute cs.valid?
      assert cs.errors[:log_source]
    end

    test "requires log_target when log_source is not none" do
      s = server_fixture()

      cs =
        Release.changeset(%Release{}, %{
          server_id: s.id,
          release_command: "/opt/app/bin/app",
          log_source: "systemd"
        })

      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:log_target]
    end

    test "validates log_target by adapter (systemd unit)" do
      s = server_fixture()

      cs =
        Release.changeset(%Release{}, %{
          server_id: s.id,
          release_command: "/opt/app/bin/app",
          log_source: "systemd",
          log_target: "bad unit name!"
        })

      refute cs.valid?
      assert cs.errors[:log_target]
    end

    test "validates log_target by adapter (file path)" do
      s = server_fixture()

      cs =
        Release.changeset(%Release{}, %{
          server_id: s.id,
          log_source: "file",
          log_target: "relative/path.log"
        })

      refute cs.valid?
      assert cs.errors[:log_target]
    end
  end

  describe "effective_handle/1" do
    test "returns the name when set" do
      r = %Release{name: "web", release_command: "/opt/app/bin/app"}
      assert Release.effective_handle(r) == "web"
    end

    test "falls back to release_command basename" do
      r = %Release{name: nil, release_command: "/opt/app/bin/app"}
      assert Release.effective_handle(r) == "app"
    end

    test "returns nil when neither is set" do
      r = %Release{name: nil, release_command: nil}
      assert Release.effective_handle(r) == nil
    end
  end

  describe "uniqueness within a server" do
    test "rejects two Releases on the same Server with the same derived handle" do
      s = server_fixture()

      {:ok, _} =
        %Release{}
        |> Release.changeset(%{server_id: s.id, release_command: "/opt/app/bin/app"})
        |> Repo.insert()

      {:error, cs} =
        %Release{}
        |> Release.changeset(%{server_id: s.id, release_command: "/srv/other/bin/app"})
        |> Repo.insert()

      assert cs.errors[:name] || cs.errors[:release_command]
    end

    test "allows the same handle on different Servers" do
      s1 = server_fixture()
      s2 = server_fixture()

      assert {:ok, _} =
               %Release{}
               |> Release.changeset(%{server_id: s1.id, release_command: "/opt/app/bin/app"})
               |> Repo.insert()

      assert {:ok, _} =
               %Release{}
               |> Release.changeset(%{server_id: s2.id, release_command: "/opt/app/bin/app"})
               |> Repo.insert()
    end

    test "allows an explicit name to disambiguate same-basename releases" do
      s = server_fixture()

      assert {:ok, _} =
               %Release{}
               |> Release.changeset(%{server_id: s.id, release_command: "/opt/web/bin/app"})
               |> Repo.insert()

      assert {:ok, _} =
               %Release{}
               |> Release.changeset(%{
                 server_id: s.id,
                 name: "worker",
                 release_command: "/opt/worker/bin/app"
               })
               |> Repo.insert()
    end
  end
end
