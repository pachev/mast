defmodule Mast.Apps.Probe.Stub do
  @moduledoc """
  Test/dev stub for the apps probe. Backed by the application env, so
  tests can plant a fixture before exercising the worker.

      Application.put_env(:mast, Mast.Apps.Probe.Stub, [
        {release.id, {:ok, [%{name: "mast_web", status: "running", ...}]}}
      ])
  """
  @behaviour Mast.Apps.Probe

  alias Mast.Fleet.Release

  @detail_key Module.concat(__MODULE__, Detail)

  @impl true
  def probe(%Release{id: id}) do
    case Application.get_env(:mast, __MODULE__, []) do
      list when is_list(list) ->
        case List.keyfind(list, id, 0) do
          {_, response} -> response
          nil -> {:ok, []}
        end

      _ ->
        {:ok, []}
    end
  end

  @impl true
  def probe_detail(%Release{id: id}, app_name) do
    case Application.get_env(:mast, @detail_key, []) do
      list when is_list(list) ->
        case List.keyfind(list, {id, app_name}, 0) do
          {_, response} -> response
          nil -> {:error, :no_planted_detail}
        end

      _ ->
        {:error, :no_planted_detail}
    end
  end

  @doc "Convenience for tests."
  def plant(%Release{id: id}, response) do
    current = Application.get_env(:mast, __MODULE__, [])

    Application.put_env(
      :mast,
      __MODULE__,
      List.keystore(current, id, 0, {id, response})
    )
  end

  @doc "Convenience for tests — plant a `probe_detail/2` response."
  def plant_detail(%Release{id: id}, app_name, response) do
    key = {id, app_name}
    current = Application.get_env(:mast, @detail_key, [])

    Application.put_env(
      :mast,
      @detail_key,
      List.keystore(current, key, 0, {key, response})
    )
  end

  @doc "Clears all planted responses."
  def reset do
    Application.put_env(:mast, __MODULE__, [])
    Application.put_env(:mast, @detail_key, [])
  end
end
