defmodule Mast.Apps.Probe.RpcExec do
  @moduledoc """
  Production probe implementation.

  Invokes `<release_command> rpc <expression>` over SSH and parses the
  result. The expression returns a JSON-serialisable list of running
  applications with version, memory, process count, and uptime.

  Why exec, not disterl?
  ----------------------

  Mix releases ship with a `bin/<name> rpc` command that connects to the
  running node and evaluates an Elixir expression. The cookie and
  distribution port are already configured inside the release; mast
  doesn't have to know either of them. One SSH command per probe, no
  EPMD tunneling, no extra network policy. See ADR 0004 (revised).

  Remote requirement: the release must support `rpc` (every recent
  `mix release` does).
  """
  @behaviour Mast.Apps.Probe

  alias Mast.SSH

  require Logger

  @impl true
  def probe(%{release_command: nil}), do: {:error, :release_command_not_set}
  def probe(%{release_command: ""}), do: {:error, :release_command_not_set}

  @timeout_ms 15_000

  def probe(server) do
    parent = self()

    task =
      Task.Supervisor.async_nolink(Mast.TaskSupervisor, fn ->
        send(parent, :probe_started)
        SSH.run(server, command(server))
      end)

    case Task.yield(task, @timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, output}} ->
        parse(output)

      {:ok, {:error, reason}} ->
        Logger.warning("AppProbe SSH failed for server=#{server.id}: #{inspect(reason)}")
        {:error, friendly_error(reason)}

      {:exit, reason} ->
        Logger.error("AppProbe crashed for server=#{server.id}: #{inspect(reason)}")
        {:error, "probe crashed: #{inspect(reason)}"}

      nil ->
        Logger.warning("AppProbe timed out after #{@timeout_ms}ms for server=#{server.id}")
        {:error, :timeout}
    end
  end

  defp command(server) do
    # Single-quote the expression so the remote shell passes it verbatim
    # to `bin/<release> rpc`. The expression is hard-coded here and
    # contains no operator input, so injection isn't a risk — but we still
    # validate that release_command itself is an absolute path with no
    # newlines (see Server.monitoring_changeset/2).
    "#{server.release_command} rpc '#{expression()}'"
  end

  # Returns one line of JSON. We sample BEAM-wide stats once and attach
  # them to every app row so the dashboard has consistent numbers per
  # probe. `:erlang.statistics(:wall_clock)` gives the BEAM's uptime in
  # ms since boot, which we report as the per-app uptime too (no
  # per-application start-time API works reliably across OTP versions).
  # The double-quote chars are escaped because we wrap the whole thing
  # in single quotes for the remote shell.
  @expression ~S'''
  {wall_ms, _} = :erlang.statistics(:wall_clock); uptime_s = div(wall_ms, 1000); mem_mb = Float.round(:erlang.memory(:total) / 1_048_576, 1); procs = :erlang.system_info(:process_count); node = Atom.to_string(Node.self()); :io.format("~ts~n", [Jason.encode!(Enum.map(:application.which_applications(), fn {n, _, v} -> %{name: Atom.to_string(n), version: to_string(v), status: "running", memory_mb: mem_mb, processes: procs, uptime_seconds: uptime_s, node_name: node} end))])
  '''

  defp expression, do: String.trim(@expression)

  # Turns a sshkit error tuple into a human-readable string for the UI.
  defp friendly_error({:non_zero_exit, exit, output}) when is_binary(output) do
    cond do
      String.contains?(output, "fully qualified hostnames") ->
        "Remote BEAM can't form a node name (FQDN issue). " <>
          "Set RELEASE_DISTRIBUTION=sname or RELEASE_NODE=<name>@<ip> in the release env. " <>
          "Original: #{first_line(output)}"

      String.contains?(output, "noconnection") ->
        "Could not connect to the running BEAM node. " <>
          "Check that the release is up and the cookie matches. " <>
          "Original: #{first_line(output)}"

      String.contains?(output, "No such file") ->
        "release_command not found on the host: #{first_line(output)}"

      true ->
        "exit #{exit}: #{first_line(output)}"
    end
  end

  defp friendly_error(other), do: inspect(other)

  defp first_line(s) do
    s
    |> String.split("\n", trim: true)
    |> Enum.reject(&(&1 == ""))
    |> List.last()
    |> Kernel.||("")
    |> String.slice(0, 240)
  end

  defp parse(output) do
    # rpc may emit warning lines before the JSON. Take the last non-empty line.
    output
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case Jason.decode(line) do
        {:ok, list} when is_list(list) -> list
        _ -> nil
      end
    end)
    |> case do
      nil ->
        {:error, {:parse_failed, output}}

      list ->
        {:ok,
         Enum.map(list, fn obs ->
           %{
             name: obs["name"],
             node_name: obs["node_name"],
             version: obs["version"],
             status: obs["status"] || "running",
             memory_mb: obs["memory_mb"],
             processes: obs["processes"],
             uptime_seconds: obs["uptime_seconds"]
           }
         end)}
    end
  end
end
