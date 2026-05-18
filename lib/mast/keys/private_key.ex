defmodule Mast.Keys.PrivateKey do
  @moduledoc """
  An SSH private key Mast can use to connect to a server.

  The `body` field stores the PEM body encrypted at rest via Cloak. Only
  `Mast.Keys.material/1` ever returns the plaintext, and only at the call
  site that needs it (the SSHKit executor).

  See ADR 0006.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mast.Keys.Parser

  @derive {Inspect, except: [:body]}

  schema "private_keys" do
    field :name, :string
    field :body, Mast.Encrypted.Binary
    field :fingerprint, :string
    field :algorithm, :string
    field :comment, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(key, attrs) do
    key
    |> cast(attrs, [:name, :body])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_body()
    |> unique_constraint(:name)
    |> unique_constraint(:fingerprint,
      message: "this key is already registered"
    )
  end

  defp validate_body(changeset) do
    case get_field(changeset, :body) do
      nil ->
        add_error(changeset, :body, "can't be blank")

      "" ->
        add_error(changeset, :body, "can't be blank")

      body ->
        case Parser.parse(body) do
          {:ok, %{encrypted?: true}} ->
            add_error(
              changeset,
              :body,
              "encrypted private keys are not supported (decrypt first)"
            )

          {:ok, info} ->
            changeset
            |> put_change(:algorithm, info.algorithm)
            |> put_change(:fingerprint, info.fingerprint)
            |> put_change(:comment, info.comment)

          {:error, :too_large} ->
            add_error(changeset, :body, "is too large (max 16KB)")

          {:error, _} ->
            add_error(changeset, :body, "is not a valid private key in PEM/OpenSSH format")
        end
    end
  end
end
