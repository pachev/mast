defmodule Mast.Fleet.Projects do
  @moduledoc """
  Context for the Project organizational lens over Servers.

  A Project groups Servers. Assignment is many-Servers-to-one-Project;
  Servers without a Project still render in the Fleet, just not under a
  group header. See CONTEXT.md and issue #24.
  """
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Mast.Audit
  alias Mast.Fleet.{Project, Server}
  alias Mast.Repo

  # --- Reads ---------------------------------------------------------------

  @doc "Lists projects, ordered by name (case-insensitive via citext)."
  def list_projects do
    Project
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc "Fetches a project by id. Raises if missing."
  def get_project!(id), do: Repo.get!(Project, id)

  @doc "Returns `%{project_id => server_count}` for projects with members."
  def server_counts do
    Server
    |> where([s], not is_nil(s.project_id))
    |> group_by([s], s.project_id)
    |> select([s], {s.project_id, count(s.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Builds a changeset for forms."
  def change_project(%Project{} = p, attrs \\ %{}), do: Project.changeset(p, attrs)

  # --- Writes --------------------------------------------------------------

  @doc "Creates a project and writes a project.created audit event."
  def create_project(attrs \\ %{}) do
    Multi.new()
    |> Multi.insert(:project, Project.changeset(%Project{}, attrs))
    |> Audit.multi_log(:audit, fn %{project: p} ->
      %{
        event_type: "project.created",
        subject_type: "Project",
        subject_id: p.id,
        metadata: %{"name" => p.name, "color" => p.color}
      }
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{project: p}} -> {:ok, p}
      {:error, :project, cs, _} -> {:error, cs}
    end
  end

  @doc """
  Updates a project. Emits at most one audit event per changed dimension
  (`project.renamed` and/or `project.recolored`). A no-op update emits
  nothing.
  """
  def update_project(%Project{} = p, attrs) do
    cs = Project.changeset(p, attrs)

    Multi.new()
    |> Multi.update(:project, cs)
    |> log_rename_if_changed(p, cs)
    |> log_recolor_if_changed(p, cs)
    |> Repo.transaction()
    |> case do
      {:ok, %{project: p}} -> {:ok, p}
      {:error, :project, cs, _} -> {:error, cs}
    end
  end

  @doc """
  Deletes a project. Atomically:

  - removes the row
  - emits `project.deleted`
  - emits one `server.project_unassigned` per Server that referenced it
    (the FK uses `on_delete: :nilify_all`, so the Server rows are
    preserved with `project_id = nil`)
  """
  def delete_project(%Project{} = p) do
    affected = affected_server_ids(p.id)

    Multi.new()
    |> Multi.delete(:project, p)
    |> Audit.multi_log(:audit, %{
      event_type: "project.deleted",
      subject_type: "Project",
      subject_id: p.id,
      metadata: %{"name" => p.name}
    })
    |> log_cascade_unassigns(affected, p)
    |> Repo.transaction()
    |> case do
      {:ok, %{project: p}} -> {:ok, p}
      {:error, :project, cs, _} -> {:error, cs}
    end
  end

  @doc """
  Assigns a Server to a Project. No-op (no extra audit event) if the
  Server already belongs to that Project.
  """
  def assign_server(%Server{project_id: pid} = s, %Project{id: pid}), do: {:ok, s}

  def assign_server(%Server{} = s, %Project{} = p) do
    cs = Server.changeset(s, %{project_id: p.id})

    Multi.new()
    |> Multi.update(:server, cs)
    |> Audit.multi_log(:audit, fn %{server: s} ->
      %{
        event_type: "server.project_assigned",
        subject_type: "Server",
        subject_id: s.id,
        metadata: %{"project_id" => p.id, "project_name" => p.name}
      }
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{server: s}} -> {:ok, s}
      {:error, :server, cs, _} -> {:error, cs}
    end
  end

  @doc "Clears a Server's project assignment. No-op if already unassigned."
  def unassign_server(%Server{project_id: nil} = s), do: {:ok, s}

  def unassign_server(%Server{} = s) do
    prior_id = s.project_id
    cs = Server.changeset(s, %{project_id: nil})

    Multi.new()
    |> Multi.update(:server, cs)
    |> Audit.multi_log(:audit, fn %{server: s} ->
      %{
        event_type: "server.project_unassigned",
        subject_type: "Server",
        subject_id: s.id,
        metadata: %{"project_id" => prior_id}
      }
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{server: s}} -> {:ok, s}
      {:error, :server, cs, _} -> {:error, cs}
    end
  end

  # --- Helpers -------------------------------------------------------------

  defp affected_server_ids(project_id) do
    Server
    |> where([s], s.project_id == ^project_id)
    |> select([s], s.id)
    |> Repo.all()
  end

  defp log_rename_if_changed(multi, %Project{name: old}, cs) do
    case Ecto.Changeset.get_change(cs, :name) do
      nil ->
        multi

      new when new == old ->
        multi

      new ->
        Audit.multi_log(multi, :audit_rename, fn %{project: p} ->
          %{
            event_type: "project.renamed",
            subject_type: "Project",
            subject_id: p.id,
            metadata: %{"from" => old, "to" => new}
          }
        end)
    end
  end

  defp log_recolor_if_changed(multi, %Project{color: old}, cs) do
    case Ecto.Changeset.get_change(cs, :color) do
      nil ->
        multi

      new when new == old ->
        multi

      new ->
        Audit.multi_log(multi, :audit_recolor, fn %{project: p} ->
          %{
            event_type: "project.recolored",
            subject_type: "Project",
            subject_id: p.id,
            metadata: %{"from" => old, "to" => new}
          }
        end)
    end
  end

  defp log_cascade_unassigns(multi, [], _project), do: multi

  defp log_cascade_unassigns(multi, server_ids, %Project{} = p) do
    Enum.reduce(server_ids, multi, fn server_id, acc ->
      Audit.multi_log(acc, {:audit_unassign, server_id}, %{
        event_type: "server.project_unassigned",
        subject_type: "Server",
        subject_id: server_id,
        metadata: %{"project_id" => p.id, "project_name" => p.name, "cause" => "project_deleted"}
      })
    end)
  end
end
