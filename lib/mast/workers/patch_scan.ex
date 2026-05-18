defmodule Mast.Workers.PatchScan do
  @moduledoc """
  Scans a server for available OS package updates.

  v0.2 supports apt only (Ubuntu/Debian). Other package managers
  (dnf, pacman, zypper) noop until we add their parsers.

  Triggered weekly by cron (Sunday 00:00) and on-demand from the UI.
  Stores `updates_available` count + raw `last_scan` payload on the
  server row.
  """
  use Oban.Worker,
    queue: :checks,
    max_attempts: 3,
    unique: [period: 60, fields: [:worker, :args]]

  alias Mast.Fleet
  alias Mast.Patches.Apt
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

    case scan(server) do
      {:ok, scan} ->
        # Atom-keyed map in memory → string-keyed for jsonb round-trip.
        # Keeps broadcasts and refetches indistinguishable in the LV.
        normalised = stringify(scan)

        {:ok, updated} =
          Fleet.record_scan(server, %{
            updates_available: scan.total,
            last_scan: normalised
          })

        broadcast({:server_updated, updated})
        :ok

      :skip ->
        broadcast({:scan_failed, server.id, "no supported package manager on this server"})
        :ok

      {:error, reason} ->
        require Logger

        Logger.warning("PatchScan failed for server #{server.name}: #{inspect(reason)}")

        broadcast({:scan_failed, server.id, format_reason(reason)})
        :ok
    end
  end

  defp format_reason({:non_zero_exit, code, output}) do
    trimmed = output |> to_string() |> String.trim() |> String.slice(0, 200)
    "exited #{code}: #{trimmed}"
  end

  defp format_reason(reason), do: reason |> inspect() |> String.slice(0, 200)

  defp scan(%{package_manager: "apt"} = server) do
    update_cmd = sudo(server, "apt-get update -qq")
    list_cmd = "LANG=C apt list --upgradable 2>/dev/null"

    with {:ok, _} <- SSH.run(server, update_cmd),
         {:ok, out} <- SSH.run(server, list_cmd) do
      {:ok, Apt.parse(out)}
    end
  end

  defp scan(_), do: :skip

  defp sudo(%{user: "root"}, cmd), do: cmd
  defp sudo(_server, cmd), do: "sudo -n " <> cmd

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)
  end

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other

  defp broadcast(msg), do: Phoenix.PubSub.broadcast(Mast.PubSub, "servers", msg)
end
