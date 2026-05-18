defmodule Mast.Workers.ConnectionCheck do
  @moduledoc """
  Probes a server over SSH, collects host metrics, persists them.

  Two entry points:

  - `%{"server_id" => id}` — runs a check against one server.
  - `%{"all" => true}` — fan-out: enqueues one job per known server.
    Used by the every-minute cron entry in `config :mast, Oban`.

  On success: `status = "up"`, metrics populated, `last_seen_at` set,
  `unreachable_count` cleared.

  On any SSH failure: `status = "down"`, `unreachable_count` bumped.
  Backoff lives in the scheduler (see ADR 0005); this worker just records.

  Broadcasts on the "servers" PubSub topic so dashboard LiveViews refresh.
  """
  use Oban.Worker,
    queue: :checks,
    max_attempts: 3,
    unique: [period: 50, fields: [:worker, :args]]

  alias Mast.Fleet
  alias Mast.Hosts.{Metrics, OS}
  alias Mast.SSH

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"all" => true}}) do
    Enum.each(Fleet.list_servers(), fn s ->
      __MODULE__.new(%{server_id: s.id}) |> Oban.insert!()
    end)

    :ok
  end

  def perform(%Oban.Job{args: %{"server_id" => server_id}}) do
    server = Fleet.get_server!(server_id)

    case probe(server) do
      {:ok, attrs} ->
        {:ok, updated} = Fleet.record_metrics(server, attrs)
        broadcast({:server_updated, updated})
        :ok

      {:error, _reason} ->
        {:ok, updated} = Fleet.mark_unreachable(server)
        broadcast({:server_updated, updated})
        :ok
    end
  end

  defp probe(server) do
    with {:ok, os} <- SSH.run(server, "cat /etc/os-release"),
         {:ok, top} <- SSH.run(server, "top -bn1 | head -3"),
         {:ok, free} <- SSH.run(server, "free -m"),
         {:ok, df} <- SSH.run(server, "df -h /") do
      os_info = OS.parse(os)

      {:ok,
       %{
         os_id: os_info.os_id,
         package_manager: os_info.package_manager,
         cpu: Metrics.parse_cpu(top),
         memory: Metrics.parse_memory(free),
         disk: Metrics.parse_disk(df)
       }}
    end
  end

  defp broadcast(msg), do: Phoenix.PubSub.broadcast(Mast.PubSub, "servers", msg)
end
