defmodule Mast.Repo.Migrations.AddCpuCoresToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :cpu_cores, :integer
    end
  end
end
