defmodule Mast.Workers.Ticker do
  @moduledoc """
  Sub-minute heartbeat that enqueues ConnectionCheck fan-out jobs.

  Cron only goes down to 1m. For dev/test we want faster feedback, so this
  GenServer fires every `:check_interval_ms` (default 30_000) and inserts
  one fan-out job. Oban's `:unique` guard on the worker prevents duplicates
  if a previous tick is still running.

  Disabled by default in `:test`. See `config :mast, :ticker_enabled`.
  """
  use GenServer

  require Logger

  @default_interval_ms 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if Application.get_env(:mast, :ticker_enabled, true) do
      interval = Application.get_env(:mast, :check_interval_ms, @default_interval_ms)
      Process.send_after(self(), :tick, interval)
      {:ok, %{interval: interval}}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:tick, state) do
    case Mast.Workers.ConnectionCheck.new(%{all: true}) |> Oban.insert() do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("Ticker failed to enqueue: #{inspect(reason)}")
    end

    Process.send_after(self(), :tick, state.interval)
    {:noreply, state}
  end
end
