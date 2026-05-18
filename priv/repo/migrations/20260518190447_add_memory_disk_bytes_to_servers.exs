defmodule Mast.Repo.Migrations.AddMemoryDiskBytesToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :memory_total_mb, :integer
      add :memory_used_mb, :integer
      add :disk_total_gb, :float
      add :disk_used_gb, :float
    end
  end
end
