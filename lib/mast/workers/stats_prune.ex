defmodule Mast.Workers.StatsPrune do
  @moduledoc """
  Deletes `server_stats` rows past their tier's retention window. Runs
  hourly from the Oban cron (see config). See ADR 0010 for the tier table.
  """
  use Oban.Worker, queue: :checks, max_attempts: 3

  import Ecto.Query
  require Logger

  alias Mast.Fleet.ServerStat
  alias Mast.Repo

  @retention_seconds %{
    "1m" => 3_600,
    "10m" => 12 * 3_600,
    "20m" => 86_400,
    "120m" => 7 * 86_400,
    "480m" => 30 * 86_400
  }

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    Enum.each(@retention_seconds, fn {bucket, seconds} ->
      cutoff = DateTime.add(now, -seconds, :second)

      {count, _} =
        Repo.delete_all(
          from s in ServerStat,
            where: s.bucket == ^bucket and s.recorded_at < ^cutoff
        )

      if count > 0 do
        Logger.info("StatsPrune deleted #{count} #{bucket} rows older than #{seconds}s")
      end
    end)

    :ok
  end
end
