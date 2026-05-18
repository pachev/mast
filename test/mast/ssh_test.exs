defmodule Mast.SSHTest do
  use ExUnit.Case, async: false

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
end
