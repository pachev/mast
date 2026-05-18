defmodule Mast.VaultTest do
  use ExUnit.Case, async: true

  alias Mast.Vault

  test "round-trips arbitrary binary data" do
    plaintext = "-----BEGIN OPENSSH PRIVATE KEY-----\nabc123\n-----END OPENSSH PRIVATE KEY-----\n"

    {:ok, ciphertext} = Vault.encrypt(plaintext)
    assert is_binary(ciphertext)
    refute ciphertext == plaintext
    refute String.contains?(ciphertext, "abc123")

    {:ok, decrypted} = Vault.decrypt(ciphertext)
    assert decrypted == plaintext
  end

  test "ciphertext is non-deterministic (fresh nonce each call)" do
    plaintext = "same input"

    {:ok, a} = Vault.encrypt(plaintext)
    {:ok, b} = Vault.encrypt(plaintext)

    refute a == b
    {:ok, ^plaintext} = Vault.decrypt(a)
    {:ok, ^plaintext} = Vault.decrypt(b)
  end

  test "decrypt does not return plaintext on tampered ciphertext" do
    {:ok, ct} = Vault.encrypt("secret")

    # Flip the last byte (the AES-GCM auth tag).
    tampered = :binary.part(ct, 0, byte_size(ct) - 1) <> <<0>>

    # Cloak's contract: on auth failure it returns {:ok, :error} rather than
    # an error tuple. Either way, callers must never receive the plaintext.
    case Vault.decrypt(tampered) do
      {:ok, :error} -> :ok
      {:error, _} -> :ok
      {:ok, other} -> flunk("decrypted tampered ciphertext to: #{inspect(other)}")
    end
  end
end
