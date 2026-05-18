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

  @callback probe(server :: Mast.Fleet.Server.t()) ::
              {:ok, [observation()]} | {:error, term()}

  @doc """
  Dispatches to the configured probe implementation.
  """
  def probe(server) do
    impl = Application.get_env(:mast, :apps_probe, __MODULE__.RpcExec)
    impl.probe(server)
  end
end
