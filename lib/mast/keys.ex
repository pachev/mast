defmodule Mast.Keys do
  @moduledoc """
  Context for managing SSH private keys.

  Keys are stored with the PEM body encrypted at rest. The plaintext only
  re-enters memory at the moment `Mast.SSH` is about to dial a server, via
  `material/1`. See ADR 0006.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Mast.Audit
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
    Multi.new()
    |> Multi.insert(:key, PrivateKey.changeset(%PrivateKey{}, attrs))
    |> Audit.multi_log(:audit, fn %{key: key} ->
      %{
        event_type: "key.created",
        subject_type: "PrivateKey",
        subject_id: key.id,
        metadata: %{
          "name" => key.name,
          "algorithm" => key.algorithm,
          "fingerprint" => key.fingerprint
        }
      }
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{key: key}} -> {:ok, key}
      {:error, :key, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Deletes a key."
  def delete_key(%PrivateKey{} = k) do
    Multi.new()
    |> Multi.delete(:key, k)
    |> Audit.multi_log(:audit, %{
      event_type: "key.deleted",
      subject_type: "PrivateKey",
      subject_id: k.id,
      metadata: %{"name" => k.name, "fingerprint" => k.fingerprint}
    })
    |> Repo.transaction()
    |> case do
      {:ok, %{key: key}} -> {:ok, key}
      {:error, :key, changeset, _} -> {:error, changeset}
    end
  end

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
