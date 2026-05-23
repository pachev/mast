defmodule Mast.SSH.KeyCbTest do
  use ExUnit.Case, async: true

  alias Mast.SSH.KeyCb

  defp pem(name), do: File.read!("test/fixtures/#{name}")

  defp opts(pem), do: [key_cb_private: [pem: pem]]

  describe "user_key/2" do
    test "decodes an OpenSSH-format ed25519 private key" do
      assert {:ok, _key} = KeyCb.user_key(:"ssh-ed25519", opts(pem("test_ed25519")))
    end
  end
end
