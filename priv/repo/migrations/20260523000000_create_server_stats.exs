defmodule Mast.Repo.Migrations.CreateServerStats do
  use Ecto.Migration

  def change do
    create table(:server_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :server_id,
          references(:servers, type: :binary_id, on_delete: :delete_all),
          null: false

      add :bucket, :string, null: false
      add :recorded_at, :utc_datetime_usec, null: false
      add :stats, :map, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:server_stats, [:server_id, :bucket, :recorded_at])

    execute(
      "CREATE INDEX server_stats_recorded_at_brin ON server_stats USING BRIN (recorded_at)",
      "DROP INDEX server_stats_recorded_at_brin"
    )
  end
end
