defmodule Mast.Fleet.Project do
  @moduledoc """
  A named grouping of Servers. Purely organizational: a Project does not
  own any behaviour, it only labels the Servers that belong together.

  See `CONTEXT.md` for the term, and issue #24 for scope.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @colors ~w(slate indigo emerald amber rose violet)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "projects" do
    field :name, :string
    field :description, :string
    field :color, :string

    has_many :servers, Mast.Fleet.Server

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Returns the allowed color preset list."
  def colors, do: @colors

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :color])
    |> update_change(:name, &trim_or_nil/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:color, @colors, message: "must be one of: #{Enum.join(@colors, ", ")}")
    |> unique_constraint(:name)
  end

  defp trim_or_nil(nil), do: nil
  defp trim_or_nil(s) when is_binary(s), do: String.trim(s)
end
