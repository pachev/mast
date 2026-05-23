defmodule Mast.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :citext, null: false
      add :description, :text
      add :color, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:projects, [:name])

    alter table(:servers) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:servers, [:project_id])
  end
end
