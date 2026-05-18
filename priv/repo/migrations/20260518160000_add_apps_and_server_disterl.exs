defmodule Mast.Repo.Migrations.AddAppsAndServerDisterl do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      # Distributed-Erlang connection details for ADR 0004 app probes.
      # `erlang_cookie` is Cloak-encrypted at the application layer.
      add :node_name, :string
      add :disterl_port, :integer
      add :erlang_cookie, :binary
    end

    create table(:applications) do
      add :server_id, references(:servers, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :node_name, :string, null: false
      add :version, :string
      add :status, :string, null: false, default: "unknown"
      add :memory_mb, :float
      add :processes, :integer
      add :uptime_seconds, :integer
      add :last_seen_at, :utc_datetime_usec
      add :last_probe, :map

      timestamps(type: :utc_datetime_usec)
    end

    create index(:applications, [:server_id])
    create unique_index(:applications, [:server_id, :name])
  end
end
