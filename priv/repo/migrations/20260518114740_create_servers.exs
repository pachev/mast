defmodule Mast.Repo.Migrations.CreateServers do
  use Ecto.Migration

  def change do
    create table(:servers) do
      add :name, :string, null: false
      add :host, :string, null: false
      add :user, :string, null: false, default: "ubuntu"
      add :port, :integer, null: false, default: 22

      add :os_id, :string
      add :package_manager, :string

      add :status, :string, null: false, default: "unknown"
      add :unreachable_count, :integer, null: false, default: 0
      add :last_seen_at, :utc_datetime_usec

      # Beszel-style live metrics — last observed snapshot only.
      add :cpu, :float
      add :memory, :float
      add :disk, :float
      add :net_mb_s, :float
      add :agent_version, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:servers, [:name])
  end
end
