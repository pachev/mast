defmodule Mast.SSHTest do
  use Mast.DataCase, async: false

  alias Mast.Fleet.Server
  alias Mast.SSH
  alias Mast.SSH.Stub

  setup do
    Stub.reset()
    :ok
  end

  test "delegates to the configured impl" do
    server = %Server{name: "web-1", host: "10.0.0.7", user: "ubuntu", port: 22}
    Stub.expect(server, "uname -s", {:ok, "Linux\n"})

    assert {:ok, "Linux\n"} = SSH.run(server, "uname -s")
  end

  test "stub returns {:error, :unexpected} for unstubbed commands" do
    server = %Server{name: "web-2", host: "10.0.0.8", user: "ubuntu", port: 22}
    assert {:error, {:unexpected_command, "df -h"}} = SSH.run(server, "df -h")
  end

  test "stub records the last command per server" do
    server = %Server{name: "web-3", host: "10.0.0.9", user: "ubuntu", port: 22}
    Stub.expect(server, "echo hi", {:ok, "hi\n"})
    {:ok, _} = SSH.run(server, "echo hi")

    assert Stub.last_command(server) == "echo hi"
  end

  describe "preload_key/1" do
    test "loads the server's private_key association if not preloaded" do
      {:ok, key} =
        Mast.Keys.create_key(%{
          name: "preload-test",
          body: File.read!("test/fixtures/test_ed25519")
        })

      {:ok, server} =
        Mast.Fleet.create_server(%{
          name: "host-1",
          host: "10.0.0.7",
          private_key_id: key.id
        })

      # private_key is %Ecto.Association.NotLoaded{} at this point.
      preloaded = Mast.SSH.preload_key(server)

      assert preloaded.private_key.id == key.id
      assert is_binary(preloaded.private_key.body)
    end

    test "is a no-op when the server has no private_key_id" do
      server = %Mast.Fleet.Server{name: "no-key", host: "10.0.0.7", user: "ubuntu", port: 22}
      assert ^server = Mast.SSH.preload_key(server)
    end
  end

  describe "run_stream/3" do
    test "yields line-events for each stdout chunk and a final exit" do
      server = %Server{name: "web-4", host: "10.0.0.4", user: "ubuntu", port: 22}

      Stub.expect_stream(server, "echo a; echo b", [
        {:line, :stdout, "a\n"},
        {:line, :stdout, "b\n"},
        {:exit, 0}
      ])

      collected =
        SSH.run_stream(server, "echo a; echo b", fn event, acc -> [event | acc] end, [])
        |> Enum.reverse()

      assert collected == [
               {:line, :stdout, "a\n"},
               {:line, :stdout, "b\n"},
               {:exit, 0}
             ]
    end

    test "stub returns error event for unstubbed command" do
      server = %Server{name: "web-5", host: "10.0.0.5", user: "ubuntu", port: 22}

      events =
        SSH.run_stream(server, "df -h", fn e, acc -> [e | acc] end, [])
        |> Enum.reverse()

      assert [{:error, _}] = events
    end
  end
end
