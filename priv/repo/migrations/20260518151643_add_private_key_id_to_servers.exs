defmodule Mast.Repo.Migrations.AddPrivateKeyIdToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :private_key_id, references(:private_keys, on_delete: :nilify_all)
    end

    create index(:servers, [:private_key_id])
  end
end
