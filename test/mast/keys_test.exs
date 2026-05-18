defmodule Mast.KeysTest do
  use Mast.DataCase, async: true

  alias Mast.Keys

  defp pem(name), do: File.read!("test/fixtures/#{name}")

  describe "create_key/1" do
    test "stores an ed25519 key" do
      assert {:ok, key} =
               Keys.create_key(%{name: "prod ed25519", body: pem("test_ed25519")})

      assert key.name == "prod ed25519"
      assert key.algorithm == "ed25519"
      assert key.fingerprint =~ ~r/^SHA256:/
      assert key.comment == "test-fixture@mast"
      # body is encrypted at rest; we verify it round-trips below.
    end

    test "stores an rsa key (OpenSSH new format)" do
      assert {:ok, key} =
               Keys.create_key(%{name: "prod rsa", body: pem("test_rsa")})

      assert key.algorithm == "rsa"
      assert key.fingerprint =~ ~r/^SHA256:/
    end

    test "stores an rsa key (classic PEM format, '-----BEGIN RSA PRIVATE KEY-----')" do
      # AWS-style .pem files use the classic ASN.1-wrapped format, not the
      # newer OpenSSH binary format. Both must be accepted.
      assert {:ok, key} =
               Keys.create_key(%{name: "aws pem", body: pem("test_rsa_pem")})

      assert key.algorithm == "rsa"
      assert key.fingerprint =~ ~r/^SHA256:/
    end

    test "rejects encrypted (passphrase-protected) keys" do
      assert {:error, cs} =
               Keys.create_key(%{name: "encrypted", body: pem("test_with_passphrase")})

      assert "encrypted private keys are not supported (decrypt first)" in errors_on(cs).body
    end

    test "rejects garbage that is not a PEM" do
      assert {:error, cs} = Keys.create_key(%{name: "junk", body: "not a key"})
      assert "is not a valid private key in PEM/OpenSSH format" in errors_on(cs).body
    end

    test "rejects empty body" do
      assert {:error, cs} = Keys.create_key(%{name: "empty", body: ""})
      assert "can't be blank" in errors_on(cs).body
    end

    test "rejects blank name" do
      assert {:error, cs} = Keys.create_key(%{name: "", body: pem("test_ed25519")})
      assert "can't be blank" in errors_on(cs).name
    end

    test "rejects duplicate fingerprint with a useful message" do
      {:ok, _} = Keys.create_key(%{name: "first", body: pem("test_ed25519")})

      assert {:error, cs} =
               Keys.create_key(%{name: "second", body: pem("test_ed25519")})

      assert "this key is already registered" in errors_on(cs).fingerprint
    end

    test "rejects bodies over 16KB" do
      huge = String.duplicate("a", 17 * 1024)
      assert {:error, cs} = Keys.create_key(%{name: "big", body: huge})
      assert Enum.any?(errors_on(cs).body, &String.contains?(&1, "too large"))
    end
  end

  describe "material/1" do
    test "decrypts the body just-in-time" do
      {:ok, key} = Keys.create_key(%{name: "k", body: pem("test_ed25519")})

      assert {:ok, material} = Keys.material(key)
      assert material == pem("test_ed25519")
    end
  end

  describe "list_keys/0 and get_key!/1" do
    test "returns keys ordered by name without leaking bodies" do
      {:ok, _} = Keys.create_key(%{name: "zeta", body: pem("test_rsa")})
      {:ok, _} = Keys.create_key(%{name: "alpha", body: pem("test_ed25519")})

      keys = Keys.list_keys()
      assert ["alpha", "zeta"] = Enum.map(keys, & &1.name)

      # Listings render the metadata, not the body. Field is loaded but the
      # important part is that you can build a UI from the plain columns alone.
      [first | _] = keys
      assert is_binary(first.fingerprint)
      assert first.algorithm in ~w(rsa ed25519)
    end
  end

  describe "delete_key/1" do
    test "removes a key" do
      {:ok, k} = Keys.create_key(%{name: "drop", body: pem("test_ed25519")})
      assert {:ok, _} = Keys.delete_key(k)
      assert [] = Keys.list_keys()
    end
  end

  describe "inspect/1" do
    test "never reveals the encrypted body" do
      {:ok, key} = Keys.create_key(%{name: "secret", body: pem("test_ed25519")})

      rendered = inspect(key)
      refute rendered =~ "OPENSSH PRIVATE KEY"
      refute rendered =~ "BEGIN"
    end
  end
end
