defmodule Mast.SSH.Stub do
  @moduledoc """
  In-memory SSH executor for tests. Supervised by `Mast.Application` when
  `config :mast, :ssh, Mast.SSH.Stub` is set (see `config/test.exs`).

  - `expect/3` pre-registers a `run/2` response for a `{host, command}` pair.
  - `expect_stream/3` pre-registers an ordered list of stream events for a
    `{host, command}` pair, replayed in order by `run_stream/4`.
  """
  @behaviour Mast.SSH

  alias Mast.Fleet.Server

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(
      fn -> %{responses: %{}, streams: %{}, last: %{}} end,
      name: __MODULE__
    )
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> %{responses: %{}, streams: %{}, last: %{}} end)
  end

  def expect(%Server{} = server, command, response) do
    key = {server.host, command}

    Agent.update(__MODULE__, fn state ->
      put_in(state, [:responses, key], response)
    end)
  end

  def expect_stream(%Server{} = server, command, events) when is_list(events) do
    key = {server.host, command}

    Agent.update(__MODULE__, fn state ->
      put_in(state, [:streams, key], events)
    end)
  end

  def last_command(%Server{} = server) do
    Agent.get(__MODULE__, fn state -> state.last[server.host] end)
  end

  @impl true
  def run(%Server{} = server, command) do
    Agent.get_and_update(__MODULE__, fn state ->
      state = put_in(state, [:last, server.host], command)

      case Map.fetch(state.responses, {server.host, command}) do
        {:ok, response} -> {response, state}
        :error -> {{:error, {:unexpected_command, command}}, state}
      end
    end)
  end

  @impl true
  def run_stream(%Server{} = server, command, reducer, acc) do
    events =
      Agent.get_and_update(__MODULE__, fn state ->
        state = put_in(state, [:last, server.host], command)

        case Map.fetch(state.streams, {server.host, command}) do
          {:ok, list} -> {list, state}
          :error -> {[{:error, {:unexpected_command, command}}], state}
        end
      end)

    Enum.reduce(events, acc, reducer)
  end
end
