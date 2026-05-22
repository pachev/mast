defmodule Mast.Repo.Migrations.ConvertToBinaryIds do
  use Ecto.Migration

  @moduledoc """
  Converts every application-table primary key and foreign key from `bigint`
  to `uuid` (Ecto's `:binary_id`). See ADR 0009.

  Strategy: for each affected table, add a parallel `*_new uuid` column,
  backfill (PKs via `gen_random_uuid()`, FKs via JOIN on the old int id),
  drop old constraints and indexes, then swap the new columns into place.

  `audit_events.subject_id` is polymorphic. We backfill the three known
  `subject_type` values (`Server`, `PrivateKey`, `Release`). Any other rows
  get `subject_id = NULL` with a Logger warning.

  `audit_events.actor_id`: existing rows used `0` for the System actor; that
  becomes `NULL` post-migration.

  Oban (`oban_jobs`, `oban_peers`) is intentionally not migrated: Oban hard-
  codes `:bigserial` for `oban_jobs.id` and its engine queries rely on bigint
  semantics. Job ids never appear in URLs and have no FKs into our tables.
  """

  require Logger

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto"

    # ─── 1. add parallel id_new columns and populate ────────────────────────
    for table <- ~w(servers private_keys releases applications audit_events) do
      execute """
      ALTER TABLE #{table}
        ADD COLUMN id_new uuid NOT NULL DEFAULT gen_random_uuid()
      """
    end

    # ─── 2. add parallel FK columns ─────────────────────────────────────────
    execute "ALTER TABLE servers ADD COLUMN private_key_id_new uuid"
    execute "ALTER TABLE releases ADD COLUMN server_id_new uuid"
    execute "ALTER TABLE applications ADD COLUMN server_id_new uuid"
    execute "ALTER TABLE applications ADD COLUMN release_id_new uuid"
    execute "ALTER TABLE audit_events ADD COLUMN subject_id_new uuid"
    execute "ALTER TABLE audit_events ADD COLUMN actor_id_new uuid"

    # ─── 3. backfill FK columns via JOIN on old int ids ─────────────────────
    execute """
    UPDATE servers s
       SET private_key_id_new = pk.id_new
      FROM private_keys pk
     WHERE s.private_key_id = pk.id
    """

    execute """
    UPDATE releases r
       SET server_id_new = s.id_new
      FROM servers s
     WHERE r.server_id = s.id
    """

    execute """
    UPDATE applications a
       SET server_id_new = s.id_new
      FROM servers s
     WHERE a.server_id = s.id
    """

    execute """
    UPDATE applications a
       SET release_id_new = r.id_new
      FROM releases r
     WHERE a.release_id = r.id
    """

    # ─── 4. audit_events.subject_id (polymorphic) ───────────────────────────
    execute """
    UPDATE audit_events ae
       SET subject_id_new = s.id_new
      FROM servers s
     WHERE ae.subject_type = 'Server'
       AND ae.subject_id = s.id
    """

    execute """
    UPDATE audit_events ae
       SET subject_id_new = pk.id_new
      FROM private_keys pk
     WHERE ae.subject_type = 'PrivateKey'
       AND ae.subject_id = pk.id
    """

    execute """
    UPDATE audit_events ae
       SET subject_id_new = r.id_new
      FROM releases r
     WHERE ae.subject_type = 'Release'
       AND ae.subject_id = r.id
    """

    flush()

    warn_orphan_subjects()

    # `actor_id` was a bigint with `0` meaning "System". Post-migration,
    # System is represented as NULL. Non-zero values cannot be mapped to a
    # uuid (no users table existed), so they also become NULL with a warning.
    warn_nonzero_actors()

    # ─── 5. drop old FK constraints + indexes ───────────────────────────────
    drop_if_exists index(:servers, [:private_key_id])
    drop_if_exists index(:releases, [:server_id])
    drop_if_exists index(:applications, [:server_id])
    drop_if_exists index(:applications, [:release_id])
    drop_if_exists unique_index(:applications, [:release_id, :name])
    drop_if_exists unique_index(:applications, [:server_id, :name])
    drop_if_exists unique_index(:releases, [:server_id, :name])
    drop_if_exists index(:audit_events, [:subject_type, :subject_id])

    execute "ALTER TABLE servers DROP CONSTRAINT IF EXISTS servers_private_key_id_fkey"
    execute "ALTER TABLE releases DROP CONSTRAINT IF EXISTS releases_server_id_fkey"
    execute "ALTER TABLE applications DROP CONSTRAINT IF EXISTS applications_server_id_fkey"
    execute "ALTER TABLE applications DROP CONSTRAINT IF EXISTS applications_release_id_fkey"

    # ─── 6. drop old PK columns, rename id_new → id ─────────────────────────
    for table <- ~w(servers private_keys releases applications audit_events) do
      execute "ALTER TABLE #{table} DROP CONSTRAINT #{table}_pkey"
      execute "ALTER TABLE #{table} DROP COLUMN id"
      execute "ALTER TABLE #{table} RENAME COLUMN id_new TO id"
      execute "ALTER TABLE #{table} ALTER COLUMN id DROP DEFAULT"
      execute "ALTER TABLE #{table} ADD PRIMARY KEY (id)"
    end

    # ─── 7. drop old FK columns, rename *_new → original ────────────────────
    execute "ALTER TABLE servers DROP COLUMN private_key_id"
    execute "ALTER TABLE servers RENAME COLUMN private_key_id_new TO private_key_id"

    execute "ALTER TABLE releases DROP COLUMN server_id"
    execute "ALTER TABLE releases RENAME COLUMN server_id_new TO server_id"
    execute "ALTER TABLE releases ALTER COLUMN server_id SET NOT NULL"

    execute "ALTER TABLE applications DROP COLUMN server_id"
    execute "ALTER TABLE applications RENAME COLUMN server_id_new TO server_id"
    execute "ALTER TABLE applications ALTER COLUMN server_id SET NOT NULL"

    execute "ALTER TABLE applications DROP COLUMN release_id"
    execute "ALTER TABLE applications RENAME COLUMN release_id_new TO release_id"
    execute "ALTER TABLE applications ALTER COLUMN release_id SET NOT NULL"

    execute "ALTER TABLE audit_events DROP COLUMN subject_id"
    execute "ALTER TABLE audit_events RENAME COLUMN subject_id_new TO subject_id"

    execute "ALTER TABLE audit_events DROP COLUMN actor_id"
    execute "ALTER TABLE audit_events RENAME COLUMN actor_id_new TO actor_id"

    # ─── 8. re-add FK constraints with uuid type ────────────────────────────
    execute """
    ALTER TABLE servers
      ADD CONSTRAINT servers_private_key_id_fkey
      FOREIGN KEY (private_key_id) REFERENCES private_keys(id) ON DELETE SET NULL
    """

    execute """
    ALTER TABLE releases
      ADD CONSTRAINT releases_server_id_fkey
      FOREIGN KEY (server_id) REFERENCES servers(id) ON DELETE CASCADE
    """

    execute """
    ALTER TABLE applications
      ADD CONSTRAINT applications_server_id_fkey
      FOREIGN KEY (server_id) REFERENCES servers(id) ON DELETE CASCADE
    """

    execute """
    ALTER TABLE applications
      ADD CONSTRAINT applications_release_id_fkey
      FOREIGN KEY (release_id) REFERENCES releases(id) ON DELETE CASCADE
    """

    # ─── 9. recreate indexes ────────────────────────────────────────────────
    create index(:servers, [:private_key_id])
    create index(:releases, [:server_id])
    create unique_index(:releases, [:server_id, :name], where: "name IS NOT NULL")
    create index(:applications, [:server_id])
    create index(:applications, [:release_id])
    create unique_index(:applications, [:release_id, :name])
    create index(:audit_events, [:subject_type, :subject_id])
  end

  def down do
    raise Ecto.MigrationError,
      message:
        "Cannot reverse binary_id conversion: uuid → bigint mapping is lossy. " <>
          "Restore from a pre-migration backup if you need to roll back."
  end

  defp warn_orphan_subjects do
    %{rows: rows} =
      repo().query!("""
      SELECT subject_type, COUNT(*)::bigint
        FROM audit_events
       WHERE subject_id IS NOT NULL
         AND subject_id_new IS NULL
       GROUP BY subject_type
      """)

    Enum.each(rows, fn [subject_type, count] ->
      Logger.warning(
        "ConvertToBinaryIds: #{count} audit_events row(s) with subject_type=#{inspect(subject_type)} " <>
          "could not be mapped to a uuid (orphan or unknown subject_type); subject_id set to NULL"
      )
    end)
  end

  defp warn_nonzero_actors do
    %{rows: [[count]]} =
      repo().query!(
        "SELECT COUNT(*)::bigint FROM audit_events WHERE actor_id IS NOT NULL AND actor_id <> 0"
      )

    if count > 0 do
      Logger.warning(
        "ConvertToBinaryIds: #{count} audit_events row(s) had a non-zero actor_id; " <>
          "no users table exists to map them, so actor_id becomes NULL"
      )
    end
  end
end
