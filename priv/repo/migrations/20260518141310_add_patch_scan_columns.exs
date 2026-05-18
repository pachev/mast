defmodule Mast.Repo.Migrations.AddPatchScanColumns do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :updates_available, :integer
      add :last_scan_at, :utc_datetime_usec
      # Latest scan payload as JSON so we can show the package list later.
      add :last_scan, :map
    end
  end
end
