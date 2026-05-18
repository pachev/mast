defmodule Mast.Apps.Probe.Stub do
  @moduledoc """
  Test/dev stub for the apps probe. Backed by the application env, so
  tests can plant a fixture before exercising the worker.

      Application.put_env(:mast, Mast.Apps.Probe.Stub, [
        {server.id, {:ok, [%{name: "mast_web", status: "running", ...}]}}
      ])
  """
  @behaviour Mast.Apps.Probe

  @impl true
  def probe(server) do
    case Application.get_env(:mast, __MODULE__, []) do
      list when is_list(list) ->
        case List.keyfind(list, server.id, 0) do
          {_, response} -> response
          nil -> {:ok, []}
        end

      _ ->
        {:ok, []}
    end
  end

  @doc "Convenience for tests."
  def plant(server, response) do
    current = Application.get_env(:mast, __MODULE__, [])
    Application.put_env(:mast, __MODULE__, List.keystore(current, server.id, 0, {server.id, response}))
  end

  @doc "Clears all planted responses."
  def reset, do: Application.put_env(:mast, __MODULE__, [])
end
