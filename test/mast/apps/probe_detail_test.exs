defmodule Mast.Apps.ProbeDetailTest do
  @moduledoc """
  Contract tests for `Mast.Apps.Probe.probe_detail/2` — the richer per-app
  observation backed by `:observer_backend.*` over the same SSH `rpc`
  transport. The probe must:

    * return `{:ok, %{sys_info, sup_tree, top_memory, top_msgq}}` on success,
    * return `{:error, :observer_backend_unavailable}` when the remote BEAM
      lacks `runtime_tools` — so the LiveView can fall back without flashing
      a scary error.
  """
  use Mast.DataCase, async: false

  alias Mast.{Apps, Fleet}
  alias Mast.Apps.Probe
  alias Mast.Apps.Probe.Stub

  setup do
    Stub.reset()
    {:ok, server} = Fleet.create_server(%{name: "hermes", host: "10.0.0.1"})
    {:ok, server} = Fleet.update_monitoring(server, %{release_command: "/opt/hermes/bin/hermes"})

    Apps.upsert_from_probe(server, [
      %{name: "hermes", node_name: "h@h", status: "running"}
    ])

    {:ok, server: server}
  end

  test "delegates to the configured stub", %{server: server} do
    payload = %{
      sys_info: %{
        scheduler_utilization: 12.5,
        atom_count: 18_321,
        port_count: 42,
        ets_count: 91,
        memory_by_category: %{
          processes: 60_000_000,
          atom: 1_200_000,
          binary: 4_000_000,
          ets: 800_000,
          code: 12_000_000
        }
      },
      sup_tree: [
        %{
          name: "Hermes.Supervisor",
          pid: "<0.123.0>",
          type: "supervisor",
          depth: 0,
          children: [
            %{name: "Hermes.Repo", pid: "<0.124.0>", type: "worker", depth: 1, children: []}
          ]
        }
      ],
      top_memory: [
        %{
          name: "Hermes.Repo",
          pid: "<0.124.0>",
          memory: 1_048_576,
          reductions: 42_000,
          msg_queue_len: 0
        }
      ],
      top_msgq: [
        %{name: "Hermes.Worker", pid: "<0.200.0>", memory: 4096, reductions: 12, msg_queue_len: 7}
      ]
    }

    Stub.plant_detail(server, "hermes", {:ok, payload})

    assert {:ok, ^payload} = Probe.probe_detail(server, "hermes")
  end

  test "returns :observer_backend_unavailable when remote lacks runtime_tools", %{server: server} do
    Stub.plant_detail(server, "hermes", {:error, :observer_backend_unavailable})

    assert {:error, :observer_backend_unavailable} =
             Probe.probe_detail(server, "hermes")
  end
end
