defmodule Mast.Workers.AppProbe do
  @moduledoc """
  Probes one Release for its running Elixir applications.

  Fan-out enumerates every Release across the fleet with a non-empty
  `release_command` and enqueues one job per Release.

  See ADR 0004 (revised) for the transport choice and ADR 0008 for the
  move from per-Server to per-Release probing.
  """
  use Oban.Worker,
    queue: :checks,
    max_attempts: 3,
    unique: [period: 50, fields: [:worker, :args]]

  require Logger

  alias Mast.Apps
  alias Mast.Fleet
  alias Mast.Fleet.Release
  alias Mast.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"all" => true}}) do
    Enum.each(Fleet.list_servers(), fn server ->
      server
      |> Fleet.list_releases()
      |> Enum.each(fn release ->
        if release.release_command && release.release_command != "" do
          __MODULE__.new(%{release_id: release.id}) |> Oban.insert!()
        end
      end)
    end)

    :ok
  end

  def perform(%Oban.Job{args: %{"release_id" => release_id}}) do
    release = Repo.preload(Fleet.get_release!(release_id), :server)
    server = release.server

    Logger.metadata(
      release_id: release.id,
      server_id: server.id,
      private_key_id: server.private_key_id
    )

    case Apps.Probe.probe(release) do
      {:ok, observations} ->
        {:ok, _apps} = Apps.upsert_from_probe(release, observations)
        broadcast({:apps_updated, server.id})
        :ok

      {:error, reason} ->
        broadcast({:apps_probe_failed, server.id, reason})
        :ok
    end
  end

  # Legacy entry point for any caller still passing server_id. Resolves
  # the Server's first Release with release_command set and forwards.
  # Remove once all schedulers are on the release_id path.
  def perform(%Oban.Job{args: %{"server_id" => server_id}}) do
    server = Fleet.get_server!(server_id)

    case Fleet.list_releases(server) |> Enum.find(&runnable?/1) do
      nil -> :ok
      %Release{} = release -> perform(%Oban.Job{args: %{"release_id" => release.id}})
    end
  end

  defp runnable?(%Release{release_command: rc}) when is_binary(rc) and rc != "", do: true
  defp runnable?(_), do: false

  defp broadcast(msg), do: Phoenix.PubSub.broadcast(Mast.PubSub, "servers", msg)
end
