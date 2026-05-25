defmodule Mast.Patches.RunsTest do
  use Mast.DataCase, async: true

  alias Mast.Fleet
  alias Mast.Patches.{Run, Runs}

  defp server!(attrs \\ %{}) do
    {:ok, server} =
      Fleet.create_server(
        Map.merge(%{name: "web-#{System.unique_integer([:positive])}", host: "10.0.0.1"}, attrs)
      )

    server
  end

  describe "start_run/1" do
    test "creates a running row for the server" do
      server = server!()

      assert {:ok, %Run{} = run} =
               Runs.start_run(%{
                 server_id: server.id,
                 run_id: "r-1",
                 scope: "all"
               })

      assert run.status == "running"
      assert run.run_id == "r-1"
      assert run.scope == "all"
      assert run.log == ""
    end

    test "upserts: a new run replaces the prior row for the same server" do
      server = server!()
      {:ok, _first} = Runs.start_run(%{server_id: server.id, run_id: "r-1", scope: "all"})
      {:ok, second} = Runs.start_run(%{server_id: server.id, run_id: "r-2", scope: "all"})

      assert second.run_id == "r-2"
      assert second.status == "running"
      assert second.log == ""
      assert Runs.get_for_server(server.id).run_id == "r-2"
    end
  end

  describe "append/2" do
    test "appends lines to the log, joined by newlines" do
      server = server!()
      {:ok, run} = Runs.start_run(%{server_id: server.id, run_id: "r-1", scope: "all"})

      {:ok, run} = Runs.append(run, ["line one", "line two"])
      {:ok, run} = Runs.append(run, ["line three"])

      assert run.log == "line one\nline two\nline three"
    end

    test "no-op on empty batch" do
      server = server!()
      {:ok, run} = Runs.start_run(%{server_id: server.id, run_id: "r-1", scope: "all"})

      assert {:ok, ^run} = Runs.append(run, [])
    end
  end

  describe "finish/3" do
    test "marks done on exit 0" do
      server = server!()
      {:ok, run} = Runs.start_run(%{server_id: server.id, run_id: "r-1", scope: "all"})

      {:ok, run} = Runs.finish(run, :done, exit_code: 0)
      assert run.status == "done"
      assert run.exit_code == 0
    end

    test "marks error with reason" do
      server = server!()
      {:ok, run} = Runs.start_run(%{server_id: server.id, run_id: "r-1", scope: "all"})

      {:ok, run} = Runs.finish(run, :error, error: "boom")
      assert run.status == "error"
      assert run.error == "boom"
    end
  end

  describe "get_for_server/1" do
    test "returns nil when no run exists" do
      server = server!()
      assert Runs.get_for_server(server.id) == nil
    end
  end
end
