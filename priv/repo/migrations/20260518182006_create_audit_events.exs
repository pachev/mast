defmodule Mast.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  def change do
    create table(:audit_events) do
      add :event_type, :string, null: false
      add :actor_id, :bigint
      add :subject_type, :string
      add :subject_id, :bigint
      add :metadata, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:audit_events, [:subject_type, :subject_id])
    create index(:audit_events, [:event_type, "inserted_at desc"])
    create index(:audit_events, ["inserted_at desc"])
  end
end
