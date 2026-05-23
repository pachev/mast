defmodule Mast.Fleet.ServerStat do
  @moduledoc """
  A single time-bucketed sample of a server's metrics.

  One row per `(server_id, bucket, recorded_at)`. The smallest bucket
  (`"1m"`) is written by `Mast.Workers.StatsCollect`; larger buckets are
  averages rolled up by `Mast.Workers.StatsDownsample`. See ADR 0010.

  ## `stats` JSONB shape

  Documented here because every chart depends on it.

      %{
        "cpu" => float (percent),
        "memory" => float (percent),
        "memory_used_mb" => integer,
        "disk_root" => float (percent on /),
        "disk_used_gb" => float,
        "disks" => [
          %{"mount" => "/", "used_pct" => f, "total_gb" => f, "used_gb" => f}
        ],
        "rx_bytes_s" => float (decimal MB/s -> bytes/s),
        "tx_bytes_s" => float,
        "io_r_bytes_s" => float,
        "io_w_bytes_s" => float,
        "load_1" => float,
        "load_5" => float,
        "load_15" => float
      }

  Keys may be missing on early samples; chart consumers tolerate `nil`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @buckets ~w(1m 10m 20m 120m 480m)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "server_stats" do
    field :bucket, :string
    field :recorded_at, :utc_datetime_usec
    field :stats, :map

    belongs_to :server, Mast.Fleet.Server

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [:server_id, :bucket, :recorded_at, :stats])
    |> validate_required([:server_id, :bucket, :recorded_at, :stats])
    |> validate_inclusion(:bucket, @buckets)
    |> unique_constraint([:server_id, :bucket, :recorded_at],
      name: :server_stats_server_id_bucket_recorded_at_index
    )
  end

  def buckets, do: @buckets
end
