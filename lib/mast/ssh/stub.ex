defmodule Mast.SSH.Stub do
  @moduledoc """
  In-memory SSH executor for tests. Backed by an Agent so it works across
  processes (LiveView tests, etc.).

  Use `expect/3` to pre-register a response for a `{server.host, command}`
  pair, then call `Mast.SSH.run/2` as normal.
  """
  @behaviour Mast.SSH

  alias Mast.Fleet.Server

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{responses: %{}, last: %{}} end, name: __MODULE__)
  end

  def reset do
    ensure_started()
    Agent.update(__MODULE__, fn _ -> %{responses: %{}, last: %{}} end)
  end

  def expect(%Server{} = server, command, response) do
    ensure_started()
    key = {server.host, command}

    Agent.update(__MODULE__, fn state ->
      put_in(state, [:responses, key], response)
    end)
  end

  def last_command(%Server{} = server) do
    ensure_started()
    Agent.get(__MODULE__, fn state -> state.last[server.host] end)
  end

  @impl true
  def run(%Server{} = server, command) do
    ensure_started()

    Agent.get_and_update(__MODULE__, fn state ->
      state = put_in(state, [:last, server.host], command)

      case Map.fetch(state.responses, {server.host, command}) do
        {:ok, response} -> {response, state}
        :error -> {{:error, {:unexpected_command, command}}, state}
      end
    end)
  end

  defp ensure_started do
    case start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end
end
