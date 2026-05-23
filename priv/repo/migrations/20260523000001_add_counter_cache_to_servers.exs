defmodule Mast.Repo.Migrations.AddCounterCacheToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :last_net_counters, :map
      add :last_disk_counters, :map
    end
  end
end
