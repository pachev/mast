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

  require Logger

  alias Mast.Audit
  alias Mast.Fleet
  alias Mast.Patches.Apt
  alias Mast.SSH
  alias Mast.Workers.PatchScan

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"server_id" => server_id, "run_id" => run_id} = args
      }) do
    server = Fleet.get_server!(server_id)
    Logger.metadata(server_id: server.id, private_key_id: server.private_key_id, run_id: run_id)
    scope = Map.get(args, "scope", "all")
    package = Map.get(args, "package")

    case build_command(server, scope, package) do
      {:ok, command} ->
        outcome = stream(server, command, run_id)
        audit(server, scope, package, outcome)
        enqueue_rescan(server)
        :ok

      {:error, reason} = err ->
        audit(server, scope, package, {:error, reason})
        err
    end
  end

  defp audit(server, scope, package, outcome) do
    base = %{
      "scope" => scope,
      "package" => package,
      "server_name" => server.name
    }

    extra =
      case outcome do
        {:exit, code} -> %{"outcome" => "exit", "exit_code" => code}
        {:error, reason} -> %{"outcome" => "error", "reason" => inspect(reason)}
        :no_exit -> %{"outcome" => "no_exit"}
      end

    Audit.log(%{
      event_type: "apply.run",
      subject_type: "Server",
      subject_id: server.id,
      metadata: Map.merge(base, extra)
    })
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
      fn event, acc ->
        Phoenix.PubSub.broadcast(Mast.PubSub, topic, {:run_event, run_id, event})

        case event do
          {:exit, _} -> event
          {:error, _} -> event
          _ -> acc
        end
      end,
      :no_exit
    )
  end

  defp enqueue_rescan(server) do
    %{server_id: server.id}
    |> PatchScan.new()
    |> Oban.insert()
  end
end
