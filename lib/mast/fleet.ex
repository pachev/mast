defmodule Mast.Fleet do
  @moduledoc """
  Context for managing the set of servers Mast watches.

  This is intentionally thin. Persistence + validation only. Background
  checks (patch scan, liveness) live in `Mast.Fleet.*` workers.
  """
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Mast.Audit
  alias Mast.Fleet.Release
  alias Mast.Fleet.Server
  alias Mast.Repo

  @doc "Returns all servers, ordered by name."
  def list_servers do
    Server
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc "Fetches a server by id. Raises if missing."
  def get_server!(id), do: Repo.get!(Server, id)

  @doc "Inserts a server."
  def create_server(attrs \\ %{}) do
    Multi.new()
    |> Multi.insert(:server, Server.changeset(%Server{}, attrs))
    |> Audit.multi_log(:audit, fn %{server: s} ->
      %{
        event_type: "server.created",
        subject_type: "Server",
        subject_id: s.id,
        metadata: %{"name" => s.name, "host" => s.host, "user" => s.user, "port" => s.port}
      }
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{server: s}} -> {:ok, s}
      {:error, :server, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Deletes a server."
  def delete_server(%Server{} = s) do
    Multi.new()
    |> Multi.delete(:server, s)
    |> Audit.multi_log(:audit, %{
      event_type: "server.deleted",
      subject_type: "Server",
      subject_id: s.id,
      metadata: %{"name" => s.name, "host" => s.host}
    })
    |> Repo.transaction()
    |> case do
      {:ok, %{server: s}} ->
        Phoenix.PubSub.broadcast(Mast.PubSub, "servers", {:server_deleted, s.id})
        {:ok, s}

      {:error, :server, changeset, _} ->
        {:error, changeset}
    end
  end

  @doc "Builds a changeset for forms."
  def change_server(%Server{} = s, attrs \\ %{}), do: Server.changeset(s, attrs)

  @doc """
  Records a metrics snapshot from a server check.

  Flips status to "up" and clears the unreachable counter.
  """
  def record_metrics(%Server{} = s, attrs) do
    s
    |> Server.metrics_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a server unreachable. Bumps the counter; flips status to "down".
  """
  def mark_unreachable(%Server{} = s) do
    s
    |> Server.unreachable_changeset()
    |> Repo.update()
  end

  @doc """
  Updates os_id / package_manager only. Used when the operator pre-fills
  these (rare) or when tests need them set without going through a full check.
  """
  def update_server_meta(%Server{} = s, attrs) do
    s
    |> Server.meta_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Stores the result of a patch scan on the server row.
  """
  def record_scan(%Server{} = s, attrs) do
    s
    |> Server.scan_changeset(attrs)
    |> Repo.update()
  end

  # --- Releases --------------------------------------------------------

  @doc "Lists Releases on a Server, ordered by effective handle."
  def list_releases(%Server{id: server_id}), do: list_releases(server_id)

  def list_releases(server_id) when is_integer(server_id) do
    Release
    |> where([r], r.server_id == ^server_id)
    |> Repo.all()
    |> Enum.sort_by(&Release.effective_handle/1)
  end

  @doc """
  Fetches a Release on a Server by its effective handle. Returns the
  Release struct or `nil`.
  """
  def get_release(%Server{id: server_id}, handle), do: get_release(server_id, handle)

  def get_release(server_id, handle)
      when is_integer(server_id) and is_binary(handle) do
    Release
    |> where([r], r.server_id == ^server_id)
    |> Repo.all()
    |> Enum.find(fn r -> Release.effective_handle(r) == handle end)
  end

  @doc "Fetches a Release by id. Raises if missing."
  def get_release!(id), do: Repo.get!(Release, id)

  @doc "Inserts a Release."
  def create_release(attrs \\ %{}) do
    Multi.new()
    |> Multi.insert(:release, Release.changeset(%Release{}, attrs))
    |> Audit.multi_log(:audit, fn %{release: r} ->
      %{
        event_type: "release.created",
        subject_type: "Release",
        subject_id: r.id,
        metadata: release_metadata(r)
      }
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{release: r}} -> {:ok, r}
      {:error, :release, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Updates a Release."
  def update_release(%Release{} = r, attrs) do
    Multi.new()
    |> Multi.update(:release, Release.changeset(r, attrs))
    |> Audit.multi_log(:audit, fn %{release: updated} ->
      %{
        event_type: "release.updated",
        subject_type: "Release",
        subject_id: updated.id,
        metadata: release_metadata(updated)
      }
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{release: r}} -> {:ok, r}
      {:error, :release, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Deletes a Release."
  def delete_release(%Release{} = r) do
    Multi.new()
    |> Multi.delete(:release, r)
    |> Audit.multi_log(:audit, %{
      event_type: "release.deleted",
      subject_type: "Release",
      subject_id: r.id,
      metadata: release_metadata(r)
    })
    |> Repo.transaction()
    |> case do
      {:ok, %{release: r}} -> {:ok, r}
      {:error, :release, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Builds a changeset for Release forms."
  def change_release(%Release{} = r, attrs \\ %{}), do: Release.changeset(r, attrs)

  defp release_metadata(%Release{} = r) do
    %{
      "server_id" => r.server_id,
      "handle" => Release.effective_handle(r),
      "name" => r.name,
      "release_command" => r.release_command,
      "log_source" => r.log_source,
      "log_target" => r.log_target
    }
  end
end
