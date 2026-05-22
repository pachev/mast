defmodule Mast.Logs.Janitor do
  @moduledoc """
  Watches LiveView pids that own a log stream. When a LiveView dies
  abnormally (`terminate/2` never runs, or the BEAM restarts mid-stream),
  the Janitor force-stops the streaming Task so the remote command
  doesn't linger on the host.

  Owned solely by `Mast.Logs` — no other module talks to it.

  ## Usage

      :ok = Mast.Logs.Janitor.register(self(), stream_task_pid)
      # later, in the LiveView's terminate/2:
      :ok = Mast.Logs.Janitor.deregister(self())

  Multiple registrations per LiveView are not supported; calling
  `register/2` a second time replaces the prior entry (and stops the old
  task pid).

  See ADR 0008.
  """
  use GenServer

  @table :mast_logs_janitor

  # ---- Client ---------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records `{owner_pid, task_pid}`. Monitors `owner_pid`; on its DOWN, the
  Janitor sends an `:exit, :kill` to `task_pid` so it tears down cleanly.

  Returns `:ok`.
  """
  def register(owner_pid, task_pid) when is_pid(owner_pid) and is_pid(task_pid) do
    GenServer.call(__MODULE__, {:register, owner_pid, task_pid})
  end

  @doc "Removes the entry for `owner_pid`. Idempotent."
  def deregister(owner_pid) when is_pid(owner_pid) do
    GenServer.call(__MODULE__, {:deregister, owner_pid})
  end

  @doc "Returns the currently tracked task pid for `owner_pid`, or `nil`."
  def lookup(owner_pid) when is_pid(owner_pid) do
    case :ets.lookup(@table, owner_pid) do
      [{^owner_pid, task_pid, _ref}] -> task_pid
      [] -> nil
    end
  end

  # ---- Server ---------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, owner_pid, task_pid}, _from, state) do
    drop_existing(owner_pid)
    ref = Process.monitor(owner_pid)
    :ets.insert(@table, {owner_pid, task_pid, ref})
    {:reply, :ok, state}
  end

  def handle_call({:deregister, owner_pid}, _from, state) do
    drop_existing(owner_pid)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case :ets.lookup(@table, pid) do
      [{^pid, task_pid, _}] ->
        :ets.delete(@table, pid)
        kill(task_pid)

      [] ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp drop_existing(owner_pid) do
    case :ets.lookup(@table, owner_pid) do
      [{^owner_pid, task_pid, ref}] ->
        Process.demonitor(ref, [:flush])
        :ets.delete(@table, owner_pid)
        kill(task_pid)

      [] ->
        :ok
    end
  end

  defp kill(task_pid) when is_pid(task_pid) do
    if Process.alive?(task_pid), do: Process.exit(task_pid, :kill)
    :ok
  end
end
