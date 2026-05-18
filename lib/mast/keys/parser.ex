defmodule Mast.Keys.Parser do
  @moduledoc """
  Pure parser for OpenSSH-format private keys. Extracts the metadata we
  need (algorithm, fingerprint, comment, encrypted?) without ever leaking
  or persisting the key body.

  OpenSSH new-format private key layout (RFC-ish):

      "openssh-key-v1\\0"
      ssh-string  cipher           # "none" if unencrypted, else "aes256-ctr" etc.
      ssh-string  kdf
      ssh-string  kdf-options
      uint32      num-keys         # always 1 in practice
      ssh-string  public-key-blob  # begins with ssh-string algorithm
      ssh-string  encrypted-block  # if cipher == "none", contains:
                                   #   uint32 checkint1
                                   #   uint32 checkint2  (equals checkint1)
                                   #   private-key payload
                                   #   ssh-string comment
                                   #   padding

  An ssh-string is `<<len::32, bytes::binary-size(len)>>`.
  """

  @max_size 16 * 1024

  @type info :: %{
          algorithm: String.t(),
          fingerprint: String.t(),
          comment: String.t() | nil,
          encrypted?: boolean()
        }

  @doc """
  Parses a PEM-encoded OpenSSH private key. Returns `{:ok, info}` or
  `{:error, atom}` — never returns the key body.
  """
  @spec parse(binary()) :: {:ok, info()} | {:error, atom()}
  def parse(pem) when is_binary(pem) do
    cond do
      byte_size(pem) > @max_size -> {:error, :too_large}
      byte_size(pem) == 0 -> {:error, :empty}
      true -> do_parse(pem)
    end
  end

  def parse(_), do: {:error, :not_a_string}

  defp do_parse(pem) do
    with [{{:no_asn1, :new_openssh}, body, _}] <- safe_pem_decode(pem),
         <<"openssh-key-v1", 0, rest::binary>> <- body,
         {:ok, cipher, rest} <- ssh_string(rest),
         {:ok, _kdf, rest} <- ssh_string(rest),
         {:ok, _kdfopts, rest} <- ssh_string(rest),
         <<_num_keys::32, rest::binary>> <- rest,
         {:ok, pub_blob, rest} <- ssh_string(rest),
         {:ok, algo_name, _} <- ssh_string(pub_blob),
         {:ok, comment} <- comment_for(cipher, rest) do
      {:ok,
       %{
         algorithm: normalise_algo(algo_name),
         fingerprint: fingerprint(pub_blob),
         comment: comment,
         encrypted?: cipher != "none"
       }}
    else
      _ -> {:error, :invalid_format}
    end
  end

  defp safe_pem_decode(pem) do
    try do
      :public_key.pem_decode(pem)
    rescue
      _ -> []
    end
  end

  defp ssh_string(<<len::32, str::binary-size(len), rest::binary>>), do: {:ok, str, rest}
  defp ssh_string(_), do: :error

  # When the key is unencrypted, we can read the comment from the trailing
  # encrypted-block. When encrypted, we can't, and we don't care — we're
  # going to reject the key anyway.
  defp comment_for("none", rest) do
    with {:ok, plain, _} <- ssh_string(rest),
         <<c1::32, c2::32, _payload::binary>> = plain,
         true <- c1 == c2 do
      {:ok, extract_comment(plain)}
    else
      _ -> {:ok, nil}
    end
  end

  defp comment_for(_other_cipher, _rest), do: {:ok, nil}

  # The comment lives near the end of the unencrypted block, but pulling it
  # out cleanly means parsing the algorithm-specific private-key payload.
  # We take a shortcut: scan for the last ssh-string that looks like ASCII
  # before the padding. Good enough for display.
  defp extract_comment(<<_c1::32, _c2::32, rest::binary>>) do
    scan_ssh_strings(rest, nil)
  end

  defp scan_ssh_strings(<<len::32, str::binary-size(len), rest::binary>>, last) do
    candidate = if printable_ascii?(str), do: str, else: last
    scan_ssh_strings(rest, candidate)
  end

  defp scan_ssh_strings(_, last), do: last

  defp printable_ascii?(""), do: false

  defp printable_ascii?(bin) when is_binary(bin) do
    bin |> :binary.bin_to_list() |> Enum.all?(&(&1 >= 32 and &1 < 127))
  end

  defp fingerprint(pub_blob) do
    "SHA256:" <> (:crypto.hash(:sha256, pub_blob) |> Base.encode64(padding: false))
  end

  defp normalise_algo("ssh-ed25519"), do: "ed25519"
  defp normalise_algo("ssh-rsa"), do: "rsa"
  defp normalise_algo("ecdsa-sha2-nistp256"), do: "ecdsa"
  defp normalise_algo("ecdsa-sha2-nistp384"), do: "ecdsa"
  defp normalise_algo("ecdsa-sha2-nistp521"), do: "ecdsa"
  defp normalise_algo(other), do: other
end
