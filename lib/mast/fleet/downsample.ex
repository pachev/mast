defmodule Mast.Fleet.Downsample do
  @moduledoc """
  Pure functions for rolling up `server_stats` rows from one bucket tier
  into the next. See ADR 0010 for the tier table.

  - `tier_transitions/0` lists the source -> target tiers in order.
  - `bucket_floor/2` truncates a `DateTime` to its bucket start.
  - `aggregate/1` collapses a list of `ServerStat` rows into one averaged
    stats map (numeric leaves get the mean; `disks[]` is averaged per mount
    key; nils are ignored; non-numeric values pass through).
  """

  alias Mast.Fleet.ServerStat

  @transitions [
    %{source: "1m", target: "10m", factor: 10, target_minutes: 10},
    %{source: "10m", target: "20m", factor: 2, target_minutes: 20},
    %{source: "20m", target: "120m", factor: 6, target_minutes: 120},
    %{source: "120m", target: "480m", factor: 4, target_minutes: 480}
  ]

  def tier_transitions, do: @transitions

  @doc """
  Floors a UTC timestamp to the start of its `minutes`-sized bucket.
  """
  @spec bucket_floor(DateTime.t(), pos_integer()) :: DateTime.t()
  def bucket_floor(%DateTime{} = dt, minutes) when is_integer(minutes) and minutes > 0 do
    unix_seconds = DateTime.to_unix(dt, :second)
    bucket_size = minutes * 60
    floored = div(unix_seconds, bucket_size) * bucket_size
    DateTime.from_unix!(floored) |> Map.put(:microsecond, {0, 6})
  end

  @doc """
  Averages a list of `ServerStat` rows into one stats map.
  """
  @spec aggregate([ServerStat.t()]) :: map()
  def aggregate([]), do: %{}

  def aggregate(rows) when is_list(rows) do
    stats_maps = Enum.map(rows, & &1.stats)
    all_keys = stats_maps |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()

    Map.new(all_keys, fn key ->
      values = Enum.map(stats_maps, &Map.get(&1, key))
      {key, aggregate_values(key, values)}
    end)
  end

  defp aggregate_values("disks", lists) do
    aggregate_disks(lists)
  end

  defp aggregate_values(_key, values) do
    numeric = Enum.filter(values, &is_number/1)

    cond do
      numeric != [] ->
        Float.round(Enum.sum(numeric) / length(numeric), 4)

      true ->
        Enum.find(values, &(not is_nil(&1)))
    end
  end

  defp aggregate_disks(lists) do
    lists
    |> Enum.filter(&is_list/1)
    |> Enum.flat_map(& &1)
    |> Enum.group_by(& &1["mount"])
    |> Enum.map(fn {mount, entries} ->
      avg = fn key ->
        nums = entries |> Enum.map(&(&1[key] || 0)) |> Enum.filter(&is_number/1)

        if nums == [] do
          0.0
        else
          Float.round(Enum.sum(nums) / length(nums), 4)
        end
      end

      %{
        "mount" => mount,
        "used_pct" => avg.("used_pct"),
        "total_gb" => avg.("total_gb"),
        "used_gb" => avg.("used_gb")
      }
    end)
  end
end
