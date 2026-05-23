defmodule Mast.Fleet.ProjectsTest do
  use Mast.DataCase, async: true

  alias Mast.Audit
  alias Mast.Fleet
  alias Mast.Fleet.Projects

  describe "create_project/1" do
    test "creates a project with name only" do
      assert {:ok, p} = Projects.create_project(%{name: "blog"})
      assert p.name == "blog"
      assert p.description in [nil, ""]
      assert p.color == nil
    end

    test "accepts a description and color from the preset palette" do
      assert {:ok, p} =
               Projects.create_project(%{
                 name: "infra",
                 description: "shared boxes",
                 color: "indigo"
               })

      assert p.description == "shared boxes"
      assert p.color == "indigo"
    end

    test "rejects a blank name" do
      assert {:error, cs} = Projects.create_project(%{name: ""})
      assert "can't be blank" in errors_on(cs).name
    end

    test "rejects a color outside the preset palette" do
      assert {:error, cs} = Projects.create_project(%{name: "x", color: "#bada55"})
      assert errors_on(cs)[:color] != nil
    end

    test "rejects a duplicate name (case-insensitive)" do
      assert {:ok, _} = Projects.create_project(%{name: "Blog"})
      assert {:error, cs} = Projects.create_project(%{name: "blog"})
      assert "has already been taken" in errors_on(cs).name
    end

    test "emits a project.created audit event" do
      {:ok, p} = Projects.create_project(%{name: "audit-create", color: "emerald"})

      assert [event] = Audit.list_for_subject("Project", p.id)
      assert event.event_type == "project.created"
      assert event.metadata["name"] == "audit-create"
      assert event.metadata["color"] == "emerald"
    end
  end

  describe "update_project/2" do
    test "renames a project and emits project.renamed" do
      {:ok, p} = Projects.create_project(%{name: "old-name"})

      assert {:ok, p2} = Projects.update_project(p, %{name: "new-name"})
      assert p2.name == "new-name"

      types =
        "Project"
        |> Audit.list_for_subject(p.id)
        |> Enum.map(& &1.event_type)

      assert "project.renamed" in types
    end

    test "recoloring emits project.recolored" do
      {:ok, p} = Projects.create_project(%{name: "rec", color: "slate"})

      assert {:ok, p2} = Projects.update_project(p, %{color: "rose"})
      assert p2.color == "rose"

      types =
        "Project"
        |> Audit.list_for_subject(p.id)
        |> Enum.map(& &1.event_type)

      assert "project.recolored" in types
    end

    test "an update that changes nothing emits no audit event beyond creation" do
      {:ok, p} = Projects.create_project(%{name: "noop"})
      {:ok, _} = Projects.update_project(p, %{name: "noop"})

      types =
        "Project"
        |> Audit.list_for_subject(p.id)
        |> Enum.map(& &1.event_type)

      assert types == ["project.created"]
    end
  end

  describe "delete_project/1" do
    test "removes the project and emits project.deleted" do
      {:ok, p} = Projects.create_project(%{name: "to-delete"})

      assert {:ok, _} = Projects.delete_project(p)
      assert Projects.list_projects() == []

      types =
        "Project"
        |> Audit.list_for_subject(p.id)
        |> Enum.map(& &1.event_type)

      assert "project.deleted" in types
    end

    test "cascade-unassigns servers, emitting one server.project_unassigned each" do
      {:ok, p} = Projects.create_project(%{name: "cascade"})

      {:ok, s1} = Fleet.create_server(%{name: "alpha", host: "10.0.0.1", project_id: p.id})
      {:ok, s2} = Fleet.create_server(%{name: "bravo", host: "10.0.0.2", project_id: p.id})

      assert {:ok, _} = Projects.delete_project(p)

      assert Fleet.get_server!(s1.id).project_id == nil
      assert Fleet.get_server!(s2.id).project_id == nil

      for s <- [s1, s2] do
        types =
          "Server"
          |> Audit.list_for_subject(s.id)
          |> Enum.map(& &1.event_type)

        assert "server.project_unassigned" in types
      end
    end
  end

  describe "assign_server/2 + unassign_server/1" do
    test "assigning sets project_id and emits server.project_assigned" do
      {:ok, p} = Projects.create_project(%{name: "assign"})
      {:ok, s} = Fleet.create_server(%{name: "needs-project", host: "10.0.0.5"})

      assert {:ok, s2} = Projects.assign_server(s, p)
      assert s2.project_id == p.id

      types =
        "Server"
        |> Audit.list_for_subject(s.id)
        |> Enum.map(& &1.event_type)

      assert "server.project_assigned" in types
    end

    test "re-assigning to the same project is a no-op (no extra audit event)" do
      {:ok, p} = Projects.create_project(%{name: "same"})
      {:ok, s} = Fleet.create_server(%{name: "stay", host: "10.0.0.6", project_id: p.id})

      assert {:ok, _} = Projects.assign_server(s, p)

      counts =
        "Server"
        |> Audit.list_for_subject(s.id)
        |> Enum.frequencies_by(& &1.event_type)

      assert Map.get(counts, "server.project_assigned", 0) <= 1
    end

    test "unassign clears project_id and emits server.project_unassigned" do
      {:ok, p} = Projects.create_project(%{name: "unassign"})
      {:ok, s} = Fleet.create_server(%{name: "leaving", host: "10.0.0.7", project_id: p.id})

      assert {:ok, s2} = Projects.unassign_server(s)
      assert s2.project_id == nil

      types =
        "Server"
        |> Audit.list_for_subject(s.id)
        |> Enum.map(& &1.event_type)

      assert "server.project_unassigned" in types
    end
  end

  describe "list_projects/0 and server_counts/0" do
    test "list_projects/0 returns rows ordered by name (case-insensitive)" do
      {:ok, _} = Projects.create_project(%{name: "Zeta"})
      {:ok, _} = Projects.create_project(%{name: "alpha"})
      {:ok, _} = Projects.create_project(%{name: "Mike"})

      assert ["alpha", "Mike", "Zeta"] = Enum.map(Projects.list_projects(), & &1.name)
    end

    test "server_counts/0 returns a map keyed by project_id with server counts" do
      {:ok, p1} = Projects.create_project(%{name: "p1"})
      {:ok, p2} = Projects.create_project(%{name: "p2"})

      {:ok, _} = Fleet.create_server(%{name: "s1", host: "10.1.0.1", project_id: p1.id})
      {:ok, _} = Fleet.create_server(%{name: "s2", host: "10.1.0.2", project_id: p1.id})
      {:ok, _} = Fleet.create_server(%{name: "s3", host: "10.1.0.3", project_id: p2.id})
      {:ok, _} = Fleet.create_server(%{name: "lone", host: "10.1.0.4"})

      counts = Projects.server_counts()
      assert counts[p1.id] == 2
      assert counts[p2.id] == 1
    end
  end
end
