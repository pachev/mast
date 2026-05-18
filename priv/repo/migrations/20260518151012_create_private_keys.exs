defmodule Mast.Repo.Migrations.CreatePrivateKeys do
  use Ecto.Migration

  def change do
    create table(:private_keys) do
      add :name, :string, null: false
      add :body, :binary, null: false
      add :fingerprint, :string, null: false
      add :algorithm, :string, null: false
      add :comment, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:private_keys, [:name])
    create unique_index(:private_keys, [:fingerprint])
  end
end
