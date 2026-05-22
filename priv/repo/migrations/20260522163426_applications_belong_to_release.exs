defmodule Mast.Repo.Migrations.ApplicationsBelongToRelease do
  use Ecto.Migration
  import Ecto.Query, only: [from: 2]

  @moduledoc """
  Promotes `applications` from per-Server to per-Release.

  Adds `release_id` (FK on `releases`), backfills every existing app to
  the oldest probe-capable Release on its Server, then makes the column
  NOT NULL. Drops the old `(server_id, name)` unique index in favour of
  `(release_id, name)` so two Releases on the same Server can each have
  their own `logger`, `stdlib`, etc.
  """

  def up do
    alter table(:applications) do
      add :release_id, references(:releases, on_delete: :delete_all)
    end

    flush()

    backfill()

    execute "ALTER TABLE applications ALTER COLUMN release_id SET NOT NULL"

    drop_if_exists unique_index(:applications, [:server_id, :name])
    create unique_index(:applications, [:release_id, :name])
    create index(:applications, [:release_id])
  end

  def down do
    drop_if_exists unique_index(:applications, [:release_id, :name])
    drop_if_exists index(:applications, [:release_id])
    create unique_index(:applications, [:server_id, :name])

    alter table(:applications) do
      remove :release_id
    end
  end

  defp backfill do
    apps_to_keep =
      Mast.Repo.all(
        from(a in "applications",
          select: %{
            id: a.id,
            server_id: a.server_id,
            name: a.name
          }
        )
      )

    Enum.each(apps_to_keep, fn %{id: app_id, server_id: server_id, name: app_name} ->
      case pick_release(server_id, app_name) do
        nil ->
          # No Release on this Server at all — drop the orphan app. Without a
          # Release we have nothing to attach it to and the NOT NULL constraint
          # would otherwise reject it.
          Mast.Repo.delete_all(from(a in "applications", where: a.id == ^app_id))

        release_id ->
          Mast.Repo.update_all(
            from(a in "applications", where: a.id == ^app_id),
            set: [release_id: release_id]
          )
      end
    end)
  end

  defp pick_release(server_id, app_name) do
    releases =
      Mast.Repo.all(
        from(r in "releases",
          where: r.server_id == ^server_id,
          order_by: [asc: r.id],
          select: %{id: r.id, name: r.name, release_command: r.release_command}
        )
      )

    # First try: name match against the Release's effective handle.
    name_match =
      Enum.find(releases, fn r ->
        handle = effective_handle(r)
        handle != nil and handle == app_name
      end)

    cond do
      name_match -> name_match.id
      first_runnable = Enum.find(releases, &runnable?/1) -> first_runnable.id
      first = List.first(releases) -> first.id
      true -> nil
    end
  end

  defp effective_handle(%{name: n}) when is_binary(n) and n != "", do: n

  defp effective_handle(%{release_command: rc}) when is_binary(rc) and rc != "",
    do: Path.basename(rc)

  defp effective_handle(_), do: nil

  defp runnable?(%{release_command: rc}) when is_binary(rc) and rc != "", do: true
  defp runnable?(_), do: false
end
