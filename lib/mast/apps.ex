defmodule Mast.Apps do
  @moduledoc """
  Context for the Elixir/OTP applications running across the fleet.

  Persistence is a snapshot only: rows are written by `Mast.Workers.AppProbe`
  and read by the dashboard. Live values (memory, uptime) are refreshed on
  demand from `MastWeb.AppLive`. See ADR 0004.
  """
  import Ecto.Query, warn: false

  alias Mast.Repo
  alias Mast.Apps.Application

  @doc "Lists every known application across the fleet, ordered by server then name."
  def list_applications do
    Application
    |> order_by([a], asc: a.name)
    |> preload(:server)
    |> Repo.all()
  end

  @doc "Lists applications attached to one server."
  def list_for_server(server_id) do
    Application
    |> where([a], a.server_id == ^server_id)
    |> order_by([a], asc: a.name)
    |> Repo.all()
  end

  @doc "Fetches one application with its server preloaded."
  def get_app!(id) do
    Application
    |> preload(:server)
    |> Repo.get!(id)
  end

  @doc """
  Reconciles the live probe result for one server against the DB. Inserts
  new rows, updates known rows, and marks now-missing apps `unreachable`.
  """
  def upsert_from_probe(server, observations) when is_list(observations) do
    now = DateTime.utc_now()
    existing = list_for_server(server.id)
    existing_by_name = Map.new(existing, &{&1.name, &1})

    seen_names =
      Enum.map(observations, fn obs ->
        attrs =
          obs
          |> Map.put(:server_id, server.id)
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

    # Mark apps that disappeared as unreachable rather than deleting them,
    # so the UI can show "was here, isn't now" history.
    stale_ids =
      existing
      |> Enum.reject(&(&1.name in seen_names))
      |> Enum.map(& &1.id)

    if stale_ids != [] do
      Application
      |> where([a], a.id in ^stale_ids)
      |> Repo.update_all(set: [status: "unreachable", updated_at: now])
    end

    {:ok, list_for_server(server.id)}
  end
end
