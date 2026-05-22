defmodule Mast.Logs.JanitorTest do
  use ExUnit.Case, async: false

  alias Mast.Logs.Janitor

  describe "register/2 and deregister/1" do
    test "tracks the task pid for the owner pid" do
      task = spawn(fn -> Process.sleep(:infinity) end)
      :ok = Janitor.register(self(), task)
      assert Janitor.lookup(self()) == task
      :ok = Janitor.deregister(self())
      assert Janitor.lookup(self()) == nil
    end

    test "deregister is idempotent" do
      :ok = Janitor.deregister(self())
      :ok = Janitor.deregister(self())
    end

    test "deregister kills the tracked task" do
      task = spawn(fn -> Process.sleep(:infinity) end)
      :ok = Janitor.register(self(), task)
      :ok = Janitor.deregister(self())

      Process.sleep(50)
      refute Process.alive?(task)
    end

    test "re-registering replaces the previous entry and kills the prior task" do
      task1 = spawn(fn -> Process.sleep(:infinity) end)
      task2 = spawn(fn -> Process.sleep(:infinity) end)

      :ok = Janitor.register(self(), task1)
      :ok = Janitor.register(self(), task2)

      Process.sleep(50)
      refute Process.alive?(task1)
      assert Process.alive?(task2)
      assert Janitor.lookup(self()) == task2

      :ok = Janitor.deregister(self())
    end
  end

  describe "owner DOWN" do
    test "kills the task when the owner dies" do
      parent = self()

      owner =
        spawn(fn ->
          task = spawn(fn -> Process.sleep(:infinity) end)
          :ok = Janitor.register(self(), task)
          send(parent, {:task, task})

          receive do
            :stop -> :ok
          end
        end)

      assert_receive {:task, task}, 1000

      Process.exit(owner, :kill)
      Process.sleep(100)

      refute Process.alive?(task)
      assert Janitor.lookup(owner) == nil
    end
  end
end
