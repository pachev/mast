defmodule Mast.Apps.Probe do
  @moduledoc """
  Behaviour for probing the running applications on a remote BEAM node.

  Implementations:

    * `Mast.Apps.Probe.Disterl` — production. Connects to the remote node
      via `Node.connect/1` and reads application state through `:rpc`.
    * `Mast.Apps.Probe.Stub` — test/dev fixture.

  The runtime impl is picked from `config :mast, :apps_probe, Module`.

  Observations are plain maps so callers (workers, LiveViews) don't need
  to know which impl produced them:

      %{
        name: "mast_web",
        version: "0.4.0",
        status: "running",
        memory_mb: 128.4,
        processes: 521,
        uptime_seconds: 12_345
      }
  """

  @type observation :: %{
          required(:name) => String.t(),
          required(:status) => String.t(),
          optional(:node_name) => String.t(),
          optional(:version) => String.t() | nil,
          optional(:memory_mb) => float() | nil,
          optional(:processes) => integer() | nil,
          optional(:uptime_seconds) => integer() | nil
        }

  @typedoc """
  Rich per-app detail. Same RPC transport as `probe/1`, but expresses
  `:observer_backend.*` calls and returns the data Observer's GUI shows.

  When the remote BEAM doesn't have `runtime_tools` loaded (so
  `:observer_backend` is undefined), `probe_detail/2` returns
  `{:error, :observer_backend_unavailable}` so callers can fall back to
  the scalar stats from `probe/1` without flashing a scary error.
  """
  @type detail :: %{
          required(:sys_info) => map(),
          required(:sup_tree) => [map()],
          required(:top_memory) => [map()],
          required(:top_msgq) => [map()]
        }

  @callback probe(server :: Mast.Fleet.Server.t()) ::
              {:ok, [observation()]} | {:error, term()}

  @callback probe_detail(server :: Mast.Fleet.Server.t(), app_name :: String.t()) ::
              {:ok, detail()} | {:error, :observer_backend_unavailable | term()}

  @optional_callbacks probe_detail: 2

  @doc """
  Dispatches to the configured probe implementation.
  """
  def probe(server) do
    impl = Application.get_env(:mast, :apps_probe, __MODULE__.RpcExec)
    impl.probe(server)
  end

  @doc """
  Dispatches the richer per-app detail probe.
  """
  def probe_detail(server, app_name) do
    impl = Application.get_env(:mast, :apps_probe, __MODULE__.RpcExec)
    impl.probe_detail(server, app_name)
  end
end
