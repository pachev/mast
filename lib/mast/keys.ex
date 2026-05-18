defmodule Mast.Keys do
  @moduledoc """
  Context for managing SSH private keys.

  Keys are stored with the PEM body encrypted at rest. The plaintext only
  re-enters memory at the moment `Mast.SSH` is about to dial a server, via
  `material/1`. See ADR 0006.
  """
  import Ecto.Query

  alias Mast.Keys.PrivateKey
  alias Mast.Repo

  @doc "Lists registered keys, ordered by name. Does not decrypt bodies."
  def list_keys do
    PrivateKey
    |> order_by([k], asc: k.name)
    |> Repo.all()
  end

  @doc "Fetches a key by id."
  def get_key!(id), do: Repo.get!(PrivateKey, id)

  @doc "Inserts a key after parsing/validating the PEM body."
  def create_key(attrs \\ %{}) do
    %PrivateKey{}
    |> PrivateKey.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Deletes a key."
  def delete_key(%PrivateKey{} = k), do: Repo.delete(k)

  @doc """
  Returns the decrypted PEM body for `key`. This is the only function that
  ever returns key material; callers must use it at the SSH dial site and
  not persist or log the result. Cloak.Ecto already decrypts the field on
  load, but we wrap the access here so the boundary is grep-able.
  """
  @spec material(PrivateKey.t()) :: {:ok, binary()} | {:error, term()}
  def material(%PrivateKey{body: body}) when is_binary(body), do: {:ok, body}
  def material(_), do: {:error, :missing_body}
end
