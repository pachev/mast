defmodule Mast.Apps do
  @moduledoc """
  Context for the Elixir/OTP applications running across the fleet.

  Persistence is a snapshot only: rows are written by `Mast.Workers.AppProbe`
  and read by the dashboard. Live values (memory, uptime) are refreshed on
  demand from `MastWeb.AppLive`. See ADR 0004.
  """
  import Ecto.Query, warn: false

  alias Mast.Apps.Application
  alias Mast.Fleet.Release
  alias Mast.Repo

  @doc "Lists every known application across the fleet, ordered by server then name."
  def list_applications do
    Application
    |> order_by([a], asc: a.name)
    |> preload([:server, :release])
    |> Repo.all()
  end

  @doc "Lists applications attached to one server (across all its Releases)."
  def list_for_server(server_id) do
    Application
    |> where([a], a.server_id == ^server_id)
    |> order_by([a], asc: a.name)
    |> Repo.all()
  end

  @doc "Lists applications attached to one Release."
  def list_for_release(%Release{id: id}), do: list_for_release(id)

  def list_for_release(release_id) when is_integer(release_id) do
    Application
    |> where([a], a.release_id == ^release_id)
    |> order_by([a], asc: a.name)
    |> Repo.all()
  end

  @doc "Fetches one application with its server + release preloaded."
  def get_app!(id) do
    Application
    |> preload([:server, :release])
    |> Repo.get!(id)
  end

  @doc """
  Reconciles a probe result for one Release against the DB. Inserts new
  rows, updates known rows, and marks now-missing apps `unreachable` —
  scoped to this Release only so two Releases on one Server don't
  clobber each other's `logger`, `stdlib`, etc.
  """
  def upsert_from_probe(%Release{} = release, observations) when is_list(observations) do
    now = DateTime.utc_now()
    existing = list_for_release(release.id)
    existing_by_name = Map.new(existing, &{&1.name, &1})

    seen_names =
      Enum.map(observations, fn obs ->
        attrs =
          obs
          |> Map.put(:server_id, release.server_id)
          |> Map.put(:release_id, release.id)
          |> Map.put(:last_seen_at, now)
          |> Map.put(:last_probe, Map.new(obs, fn {k, v} -> {to_string(k), v} end))

        case Map.fetch(existing_by_name, attrs[:name] || attrs["name"]) do
          {:ok, existing_row} ->
            existing_row
            |> Application.changeset(attrs)
            |> Repo.update!()

          :error ->
            %Application{}
            |> Application.changeset(attrs)
            |> Repo.insert!()
        end

        attrs[:name] || attrs["name"]
      end)

    stale_ids =
      existing
      |> Enum.reject(&(&1.name in seen_names))
      |> Enum.map(& &1.id)

    if stale_ids != [] do
      Application
      |> where([a], a.id in ^stale_ids)
      |> Repo.update_all(set: [status: "unreachable", updated_at: now])
    end

    {:ok, list_for_release(release.id)}
  end
end
