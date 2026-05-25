defmodule Mast.Repo.Migrations.CreatePatchRuns do
  use Ecto.Migration

  # One row per server: the *last* apply-updates run. New runs upsert over
  # the prior row (see Mast.Patches.Runs). Holds enough to reattach a
  # reloaded LiveView to an in-flight run, including the accumulated log.
  def change do
    create table(:patch_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false

      add :run_id, :string, null: false
      add :scope, :string, null: false
      add :package, :string
      add :status, :string, null: false
      add :exit_code, :integer
      add :log, :text, null: false, default: ""
      add :error, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:patch_runs, [:server_id])
  end
end
