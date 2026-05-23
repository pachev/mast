defmodule Mast.Workers.StatsDownsample do
  @moduledoc """
  Walks the `server_stats` tier chain and rolls up shorter buckets into
  longer ones. Runs every 10 minutes from the Oban cron (see config).

  For each tier transition (1m -> 10m -> 20m -> 120m -> 480m) and each
  server, it groups source rows by `bucket_floor(target_minutes)`, keeps
  only complete windows (factor source rows present, window end <= now),
  averages them in Elixir, and upserts via the unique index on
  `(server_id, bucket, recorded_at)` with `on_conflict: :nothing`.
  """
  use Oban.Worker, queue: :checks, max_attempts: 3

  import Ecto.Query

  alias Mast.Fleet.Downsample
  alias Mast.Fleet.Server
  alias Mast.Fleet.ServerStat
  alias Mast.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    now = resolve_now(args["now"])

    server_ids = Repo.all(from s in Server, select: s.id)

    Enum.each(server_ids, fn sid ->
      Enum.each(Downsample.tier_transitions(), fn t ->
        process_transition(sid, t, now)
      end)
    end)

    :ok
  end

  defp resolve_now(nil), do: DateTime.utc_now()

  defp resolve_now(s) when is_binary(s) do
    {:ok, dt, _} = DateTime.from_iso8601(s)
    dt
  end

  defp process_transition(server_id, transition, now) do
    %{source: source, target: target, factor: factor, target_minutes: minutes} = transition

    source_rows =
      Repo.all(
        from s in ServerStat,
          where: s.server_id == ^server_id and s.bucket == ^source,
          order_by: [asc: s.recorded_at]
      )

    source_rows
    |> Enum.group_by(&Downsample.bucket_floor(&1.recorded_at, minutes))
    |> Enum.each(fn {window_start, rows} ->
      maybe_insert_window(server_id, target, minutes, factor, window_start, rows, now)
    end)
  end

  defp maybe_insert_window(server_id, target, minutes, factor, window_start, rows, now) do
    window_end = DateTime.add(window_start, minutes * 60, :second)

    cond do
      length(rows) < factor ->
        :ok

      DateTime.compare(window_end, now) == :gt ->
        :ok

      true ->
        insert_window(server_id, target, window_start, rows)
    end
  end

  defp insert_window(server_id, target, window_start, rows) do
    stats = Downsample.aggregate(rows)
    now = DateTime.utc_now()

    Repo.insert_all(
      ServerStat,
      [
        %{
          id: Ecto.UUID.generate(),
          server_id: server_id,
          bucket: target,
          recorded_at: window_start,
          stats: stats,
          inserted_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:server_id, :bucket, :recorded_at]
    )

    :ok
  end
end
