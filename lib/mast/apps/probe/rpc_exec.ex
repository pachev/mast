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

  @timeout_ms 15_000

  @impl true
  def probe(%{release_command: nil}), do: {:error, :release_command_not_set}
  def probe(%{release_command: ""}), do: {:error, :release_command_not_set}

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

  @impl true
  def probe_detail(%{release_command: nil}, _), do: {:error, :release_command_not_set}
  def probe_detail(%{release_command: ""}, _), do: {:error, :release_command_not_set}

  def probe_detail(server, app_name) do
    parent = self()

    task =
      Task.Supervisor.async_nolink(Mast.TaskSupervisor, fn ->
        send(parent, :probe_detail_started)
        SSH.run(server, detail_command(server, app_name))
      end)

    case Task.yield(task, @timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, output}} ->
        parse_detail(output)

      {:ok, {:error, reason}} ->
        Logger.warning("AppProbe detail SSH failed for server=#{server.id}: #{inspect(reason)}")
        {:error, friendly_error(reason)}

      {:exit, reason} ->
        Logger.error("AppProbe detail crashed for server=#{server.id}: #{inspect(reason)}")
        {:error, "probe crashed: #{inspect(reason)}"}

      nil ->
        Logger.warning("AppProbe detail timed out for server=#{server.id}")
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

  defp detail_command(server, app_name) do
    # app_name is the atom name of an OTP application loaded on the remote
    # node. It comes from a row we previously inserted via probe/1, not from
    # operator input. Still, we sanitise to lowercase + underscore + digit
    # before interpolating — same charset as a valid OTP app name.
    safe = sanitize_app_name(app_name)
    "#{server.release_command} rpc '#{detail_expression(safe)}'"
  end

  defp sanitize_app_name(name) when is_binary(name) do
    name |> String.downcase() |> String.replace(~r/[^a-z0-9_]/, "")
  end

  # Returns one line of JSON. We sample BEAM-wide stats once and attach
  # them to every app row so the dashboard has consistent numbers per
  # probe. `:erlang.statistics(:wall_clock)` gives the BEAM's uptime in
  # ms since boot, which we report as the per-app uptime too (no
  # per-application start-time API works reliably across OTP versions).
  # The double-quote chars are escaped because we wrap the whole thing
  # in single quotes for the remote shell.
  @expression ~S'''
  {wall_ms, _} = :erlang.statistics(:wall_clock); uptime_s = div(wall_ms, 1000); mem_mb = Float.round(:erlang.memory(:total) / 1_048_576, 1); procs = :erlang.system_info(:process_count); msg_q = Enum.reduce(Process.list(), 0, fn p, acc -> case Process.info(p, :message_queue_len) do {:message_queue_len, n} -> acc + n; _ -> acc end end); otp = to_string(:erlang.system_info(:otp_release)); node = Atom.to_string(Node.self()); :io.format("~ts~n", [Jason.encode!(Enum.map(:application.which_applications(), fn {n, _, v} -> %{name: Atom.to_string(n), version: to_string(v), status: "running", memory_mb: mem_mb, processes: procs, msg_queue: msg_q, otp_release: otp, uptime_seconds: uptime_s, node_name: node} end))])
  '''

  defp expression, do: String.trim(@expression)

  # Detail expression. Runs `:observer_backend.*` calls if `runtime_tools`
  # is loaded; otherwise emits `{"error":"observer_backend_unavailable"}`
  # so the LiveView can fall back to scalar stats gracefully.
  #
  # Tree walk: `:observer_backend.app_info/1` returns a digraph-style
  # representation but it's clunky. We walk the supervision tree by hand
  # via `Supervisor.which_children/1` instead — same data, JSON-friendly.
  @detail_expression ~S'''
  try do
    Code.ensure_loaded(:observer_backend)
    if not function_exported?(:observer_backend, :sys_info, 0) do
      :io.format("~ts~n", [Jason.encode!(%{error: "observer_backend_unavailable"})])
    else
      sys = :observer_backend.sys_info()
      kv = fn k -> case List.keyfind(sys, k, 0) do {_, v} -> v; _ -> nil end end
      sched = case :scheduler.utilization(1) do
        list when is_list(list) ->
          total = Enum.find(list, fn t -> elem(t, 0) == :total end)
          case total do {:total, u, _} -> Float.round(u * 100, 1); _ -> nil end
        _ -> nil
      end
      sys_info = %{
        scheduler_utilization: sched,
        atom_count: kv.(:atom_count),
        port_count: kv.(:port_count),
        process_count: kv.(:process_count),
        ets_count: kv.(:ets_count),
        memory_by_category: %{
          processes: :erlang.memory(:processes),
          atom: :erlang.memory(:atom),
          binary: :erlang.memory(:binary),
          ets: :erlang.memory(:ets),
          code: :erlang.memory(:code),
          total: :erlang.memory(:total)
        }
      }
      app = String.to_atom("__APP__")
      sup_tree = case :application_controller.get_master(app) do
        :undefined -> []
        master ->
          case :application_master.get_child(master) do
            {root, _} when is_pid(root) ->
              walk = fn walk, pid, depth ->
                {name, type} = case Process.info(pid, [:registered_name, :dictionary]) do
                  nil -> {nil, "worker"}
                  info ->
                    rn = Keyword.get(info, :registered_name)
                    dict = Keyword.get(info, :dictionary) || []
                    initial = Keyword.get(dict, :"$initial_call")
                    ancestors = Keyword.get(dict, :"$ancestors") || []
                    t = case initial do
                      {:supervisor, _, _} -> "supervisor"
                      _ -> "worker"
                    end
                    n = cond do
                      is_atom(rn) and not is_nil(rn) -> Atom.to_string(rn)
                      match?({:supervisor, _, _}, initial) ->
                        {_, m, _} = initial
                        "#{inspect(m)} (sup)"
                      match?({_, _, _}, initial) ->
                        {m, f, a} = initial
                        "#{inspect(m)}.#{f}/#{a}"
                      true ->
                        case ancestors do
                          [a | _] when is_atom(a) -> "child of #{inspect(a)}"
                          [a | _] when is_pid(a) -> "child of #{inspect(a)}"
                          _ -> nil
                        end
                    end
                    {n, t}
                end
                children = if type == "supervisor" and depth < 3 do
                  try do
                    pid
                    |> Supervisor.which_children()
                    |> Enum.map(fn {_id, child, _t, _mods} ->
                      if is_pid(child), do: walk.(walk, child, depth + 1), else: nil
                    end)
                    |> Enum.reject(&is_nil/1)
                  rescue _ -> [] end
                else
                  []
                end
                %{name: name, pid: inspect(pid), type: type, depth: depth, children: children}
              end
              [walk.(walk, root, 0)]
            _ -> []
          end
      end
      proc_row = fn pid ->
        case Process.info(pid, [:registered_name, :memory, :reductions, :message_queue_len]) do
          nil -> nil
          info ->
            rn = Keyword.get(info, :registered_name)
            name = case rn do n when is_atom(n) and not is_nil(n) -> Atom.to_string(n); _ -> nil end
            %{
              name: name,
              pid: inspect(pid),
              memory: Keyword.get(info, :memory, 0),
              reductions: Keyword.get(info, :reductions, 0),
              msg_queue_len: Keyword.get(info, :message_queue_len, 0)
            }
        end
      end
      all = Process.list() |> Enum.map(proc_row) |> Enum.reject(&is_nil/1)
      top_memory = all |> Enum.sort_by(& &1.memory, :desc) |> Enum.take(10)
      top_msgq = all |> Enum.sort_by(& &1.msg_queue_len, :desc) |> Enum.take(10)
      payload = %{sys_info: sys_info, sup_tree: sup_tree, top_memory: top_memory, top_msgq: top_msgq}
      :io.format("~ts~n", [Jason.encode!(payload)])
    end
  rescue
    UndefinedFunctionError ->
      :io.format("~ts~n", [Jason.encode!(%{error: "observer_backend_unavailable"})])
    e ->
      :io.format("~ts~n", [Jason.encode!(%{error: "probe_detail_failed", message: Exception.message(e)})])
  end
  '''

  defp detail_expression(app_name) do
    # Keep newlines — bin/<release> rpc accepts a multiline expression
    # as one shell argument (we wrap the whole thing in single quotes).
    # Collapsing whitespace breaks `end` + next-line tokens.
    @detail_expression
    |> String.trim()
    |> String.replace("__APP__", app_name)
  end

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

  defp parse_detail(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case Jason.decode(line) do
        {:ok, %{} = m} -> m
        _ -> nil
      end
    end)
    |> case do
      nil ->
        {:error, {:parse_failed, output}}

      %{"error" => "observer_backend_unavailable"} ->
        {:error, :observer_backend_unavailable}

      %{"error" => other, "message" => msg} ->
        {:error, "#{other}: #{msg}"}

      %{"sys_info" => sys, "sup_tree" => tree, "top_memory" => mem, "top_msgq" => mq} ->
        {:ok,
         %{
           sys_info: atomize(sys),
           sup_tree: Enum.map(tree, &atomize_node/1),
           top_memory: Enum.map(mem, &atomize/1),
           top_msgq: Enum.map(mq, &atomize/1)
         }}

      _ ->
        {:error, {:parse_failed, output}}
    end
  end

  defp atomize(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), atomize(v)}
      {k, v} -> {k, atomize(v)}
    end)
  end

  defp atomize(list) when is_list(list), do: Enum.map(list, &atomize/1)
  defp atomize(v), do: v

  defp atomize_node(%{} = node) do
    base = atomize(Map.delete(node, "children"))
    children = node |> Map.get("children", []) |> Enum.map(&atomize_node/1)
    Map.put(base, :children, children)
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
             msg_queue: obs["msg_queue"],
             otp_release: obs["otp_release"],
             uptime_seconds: obs["uptime_seconds"]
           }
         end)}
    end
  end
end
