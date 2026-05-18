defmodule Mast.Workers.AppProbe do
  @moduledoc """
  Probes one server for its running Elixir applications. Mirrors
  `ConnectionCheck` in shape: single-server entry, fan-out entry, broadcasts
  on the "servers" PubSub topic.

  Skips servers with no `release_command`.

  See ADR 0004 (revised) for the transport choice.
  """
  use Oban.Worker,
    queue: :checks,
    max_attempts: 3,
    unique: [period: 50, fields: [:worker, :args]]

  alias Mast.{Apps, Fleet}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"all" => true}}) do
    Enum.each(Fleet.list_servers(), fn s ->
      if s.release_command && s.release_command != "" do
        __MODULE__.new(%{server_id: s.id}) |> Oban.insert!()
      end
    end)

    :ok
  end

  def perform(%Oban.Job{args: %{"server_id" => server_id}}) do
    server = Fleet.get_server!(server_id)

    case Apps.Probe.probe(server) do
      {:ok, observations} ->
        {:ok, _apps} = Apps.upsert_from_probe(server, observations)
        broadcast({:apps_updated, server.id})
        :ok

      {:error, reason} ->
        broadcast({:apps_probe_failed, server.id, reason})
        # Don't kill the job; the next tick will retry.
        :ok
    end
  end

  defp broadcast(msg), do: Phoenix.PubSub.broadcast(Mast.PubSub, "servers", msg)
end
