defmodule Mast.Repo.Migrations.CreateReleasesAndBackfill do
  use Ecto.Migration
  import Ecto.Query, only: [from: 2]

  def up do
    create table(:releases) do
      add :server_id, references(:servers, on_delete: :delete_all), null: false
      add :name, :string
      add :release_command, :string
      add :log_source, :string, null: false, default: "none"
      add :log_target, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:releases, [:server_id])
    create unique_index(:releases, [:server_id, :name], where: "name IS NOT NULL")

    flush()

    backfill_releases()
  end

  def down do
    drop table(:releases)
  end

  defp backfill_releases do
    now = DateTime.utc_now()

    servers =
      Mast.Repo.all(
        from s in "servers",
          where: not is_nil(s.release_command) and s.release_command != "",
          select: %{id: s.id, release_command: s.release_command}
      )

    Enum.each(servers, fn %{id: server_id, release_command: rc} ->
      {1, [%{id: release_id}]} =
        Mast.Repo.insert_all(
          "releases",
          [
            %{
              server_id: server_id,
              name: nil,
              release_command: rc,
              log_source: "none",
              log_target: nil,
              inserted_at: now,
              updated_at: now
            }
          ],
          returning: [:id]
        )

      Mast.Repo.insert_all("audit_events", [
        %{
          event_type: "release.created",
          actor_id: 0,
          subject_type: "Release",
          subject_id: release_id,
          metadata: %{"backfilled_from" => "servers.release_command"},
          inserted_at: now
        }
      ])
    end)
  end

end
