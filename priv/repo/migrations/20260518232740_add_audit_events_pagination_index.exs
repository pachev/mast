defmodule Mast.Repo.Migrations.AddAuditEventsPaginationIndex do
  use Ecto.Migration

  def change do
    create index(:audit_events, ["inserted_at DESC", "id DESC"],
             name: :audit_events_inserted_at_id_desc_index
           )
  end
end
