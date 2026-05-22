defmodule Mast.Apps.Probe do
  @moduledoc """
  Behaviour for probing the running applications on a Release.

  Implementations:

    * `Mast.Apps.Probe.RpcExec` — production. SSHs to the Release's Server
      and invokes `<release_command> rpc <expression>`.
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

  alias Mast.Fleet.Release

  @type observation :: %{
          required(:name) => String.t(),
          required(:status) => String.t(),
          optional(:node_name) => String.t(),
          optional(:version) => String.t() | nil,
          optional(:memory_mb) => float() | nil,
          optional(:processes) => integer() | nil,
          optional(:uptime_seconds) => integer() | nil
        }

  @type detail :: %{
          required(:sys_info) => map(),
          required(:sup_tree) => [map()],
          required(:top_memory) => [map()],
          required(:top_msgq) => [map()]
        }

  @callback probe(release :: Release.t()) :: {:ok, [observation()]} | {:error, term()}

  @callback probe_detail(release :: Release.t(), app_name :: String.t()) ::
              {:ok, detail()} | {:error, :observer_backend_unavailable | term()}

  @optional_callbacks probe_detail: 2

  @doc "Dispatches to the configured probe implementation."
  def probe(release) do
    impl = Application.get_env(:mast, :apps_probe, __MODULE__.RpcExec)
    impl.probe(release)
  end

  @doc "Dispatches the richer per-app detail probe."
  def probe_detail(release, app_name) do
    impl = Application.get_env(:mast, :apps_probe, __MODULE__.RpcExec)
    impl.probe_detail(release, app_name)
  end
end
