defmodule Mast.Fleet do
  @moduledoc """
  Context for managing the set of servers Mast watches.

  This is intentionally thin. Persistence + validation only. Background
  checks (patch scan, liveness) live in `Mast.Fleet.*` workers.
  """
  import Ecto.Query, warn: false

  alias Mast.Repo
  alias Mast.Fleet.Server

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
    %Server{}
    |> Server.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Deletes a server."
  def delete_server(%Server{} = s), do: Repo.delete(s)

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
end
