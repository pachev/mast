defmodule Mast.Workers.ApplyUpdates do
  @moduledoc """
  User-triggered job that runs `apt upgrade -y` (or a single package install)
  on a server and streams stdout/stderr lines over PubSub.

  Args:

      %{
        "server_id" => integer(),
        "run_id"    => binary(),
        "scope"     => "all" | "package",
        "package"   => binary()         # required when scope == "package"
      }

  Events broadcast on the `"runs:<run_id>"` topic:

      {:run_event, run_id, {:line, :stdout | :stderr, String.t()}}
      {:run_event, run_id, {:exit, integer()}}
      {:run_event, run_id, {:error, term()}}

  After a successful apply the worker enqueues a fresh `PatchScan` so the
  dashboard reflects the new `updates_available` count.

  Goes on the `:runs` queue so long-running upgrades don't starve `:checks`.
  """
  use Oban.Worker, queue: :runs, max_attempts: 1

  alias Mast.Fleet
  alias Mast.Patches.Apt
  alias Mast.SSH
  alias Mast.Workers.PatchScan

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"server_id" => server_id, "run_id" => run_id} = args
      }) do
    server = Fleet.get_server!(server_id)
    scope = Map.get(args, "scope", "all")
    package = Map.get(args, "package")

    with {:ok, command} <- build_command(server, scope, package) do
      stream(server, command, run_id)
      enqueue_rescan(server)
      :ok
    end
  end

  defp build_command(%{package_manager: "apt"} = server, "all", _) do
    update = sudo(server, "apt-get update -qq")
    upgrade = sudo(server, "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y")
    {:ok, "#{update} && #{upgrade}"}
  end

  defp build_command(%{package_manager: "apt"} = server, "package", package)
       when is_binary(package) do
    if Apt.safe_package_name?(package) do
      {:ok,
       sudo(
         server,
         "DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade " <> package
       )}
    else
      {:error, :invalid_package}
    end
  end

  defp build_command(_server, _scope, _package), do: {:error, :unsupported_package_manager}

  defp sudo(%{user: "root"}, cmd), do: cmd
  defp sudo(_server, cmd), do: "sudo -n " <> cmd

  defp stream(server, command, run_id) do
    topic = "runs:#{run_id}"

    SSH.run_stream(
      server,
      command,
      fn event, _acc ->
        Phoenix.PubSub.broadcast(Mast.PubSub, topic, {:run_event, run_id, event})
        nil
      end,
      nil
    )
  end

  defp enqueue_rescan(server) do
    %{server_id: server.id}
    |> PatchScan.new()
    |> Oban.insert()
  end
end
