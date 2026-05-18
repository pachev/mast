defmodule Mast.SSH.KeyCb do
  @moduledoc """
  Erlang :ssh `:key_cb` callback module. Provides a per-connection private
  key to `:ssh.connect/4` without ever writing it to disk.

  Pass via `key_cb: {Mast.SSH.KeyCb, [pem: <plaintext PEM>]}` in the
  connect options. The plaintext lives in the option list for the
  duration of the SSH connection only — never persisted, never logged.

  Implements :ssh_client_key_api (a subset; we don't track host keys).
  """
  @behaviour :ssh_client_key_api

  @impl true
  def add_host_key(_host, _port, _public_key, _opts), do: :ok

  @impl true
  def is_host_key(_key, _host, _port, _algorithm, _opts), do: true

  @impl true
  def user_key(_algorithm, opts) do
    with {:ok, pem} <- fetch_pem(opts),
         [entry | _] <- safe_pem_decode(pem),
         {:ok, key} <- decode_entry(entry) do
      {:ok, key}
    else
      _ -> {:error, :no_user_key}
    end
  end

  defp fetch_pem(opts) do
    private = opts[:key_cb_private] || []

    case private[:pem] do
      pem when is_binary(pem) -> {:ok, pem}
      pem when is_list(pem) -> {:ok, IO.iodata_to_binary(pem)}
      _ -> :error
    end
  end

  defp safe_pem_decode(pem) do
    :public_key.pem_decode(pem)
  rescue
    _ -> []
  end

  # Classic PEMs (`-----BEGIN RSA PRIVATE KEY-----`) get a tagged ASN.1 entry.
  defp decode_entry({tag, der, :not_encrypted}) when is_atom(tag) do
    {:ok, :public_key.der_decode(tag, der)}
  rescue
    _ -> :error
  end

  # OpenSSH new format (`-----BEGIN OPENSSH PRIVATE KEY-----`). Erlang's
  # :ssh_file.decode/2 handles the binary blob into a [{Key, Attrs}] list.
  defp decode_entry({{:no_asn1, :new_openssh}, blob, _}) do
    case :ssh_file.decode(reconstitute_pem(blob), :openssh_key) do
      [{key, _attrs} | _] -> {:ok, key}
      _ -> :error
    end
  end

  defp decode_entry(_), do: :error

  # ssh_file.decode/2 wants the wrapped PEM, not the inner blob.
  defp reconstitute_pem(blob) do
    b64 = blob |> Base.encode64() |> chunk(70)

    "-----BEGIN OPENSSH PRIVATE KEY-----\n" <>
      b64 <>
      "-----END OPENSSH PRIVATE KEY-----\n"
  end

  defp chunk(s, n),
    do:
      s
      |> String.codepoints()
      |> Enum.chunk_every(n)
      |> Enum.map_join("\n", &Enum.join/1)
      |> Kernel.<>("\n")
end
