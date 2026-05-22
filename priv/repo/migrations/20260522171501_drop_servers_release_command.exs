defmodule Mast.Repo.Migrations.DropServersReleaseCommand do
  use Ecto.Migration

  @moduledoc """
  Drops `servers.release_command`. Its content lives on `releases` now
  (ADR 0008). The column was kept across earlier commits on this branch
  so existing UIs that read it didn't break mid-refactor; nothing reads
  it anymore.
  """

  def up do
    alter table(:servers) do
      remove :release_command
    end
  end

  def down do
    alter table(:servers) do
      add :release_command, :string
    end
  end
end
