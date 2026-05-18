defmodule Mast.Repo.Migrations.AddLoadAvgToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :load_1, :float
      add :load_5, :float
      add :load_15, :float
    end
  end
end
