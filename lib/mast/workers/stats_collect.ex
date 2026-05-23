defmodule Mast.Workers.StatsCollect do
  @moduledoc """
  Collects one time-bucketed metrics sample per `up` server and writes it
  to the `server_stats` table in bucket `"1m"`.

  Triggered every minute by the Oban cron (see config). Two entry points:

  - `%{"all" => true}` — fan-out, enqueues one job per up server.
  - `%{"server_id" => id}` — runs a collect against one server.

  One combined SSH session per tick reads top, free, df, /proc/net/dev,
  /proc/diskstats, /proc/loadavg with delimiters. Bandwidth and disk I/O
  rates are computed against `last_net_counters` and `last_disk_counters`
  cached on the server row (see ADR 0010). First sample after a restart
  or new server returns 0.0 rates and primes the cache.
  """
  use Oban.Worker,
    queue: :checks,
    max_attempts: 3,
    unique: [period: 55, fields: [:worker, :args]]

  require Logger

  alias Mast.Fleet
  alias Mast.Fleet.Server
  alias Mast.Hosts.Metrics
  alias Mast.SSH

  @combined_command """
  echo __TOP__; top -bn1 | head -3; \
  echo __FREE__; free -m; \
  echo __DF__; df -P; \
  echo __NET__; cat /proc/net/dev; \
  echo __IO__; cat /proc/diskstats; \
  echo __LOAD__; cat /proc/loadavg
  """

  @doc """
  The single SSH command used to gather a sample. Exposed so tests can stub
  it without duplicating the heredoc.
  """
  def command, do: @combined_command

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"all" => true}}) do
    Fleet.list_servers()
    |> Enum.filter(&(&1.status == "up"))
    |> Enum.each(fn s ->
      __MODULE__.new(%{server_id: s.id}) |> Oban.insert!()
    end)

    :ok
  end

  def perform(%Oban.Job{args: %{"server_id" => server_id}}) do
    server = Fleet.get_server!(server_id)

    if server.status != "up" do
      :ok
    else
      Logger.metadata(server_id: server.id)
      collect(server)
    end
  end

  defp collect(%Server{} = server) do
    now = DateTime.utc_now()

    case SSH.run(server, @combined_command) do
      {:ok, output} ->
        write_sample(server, output, now)

      {:error, reason} ->
        Logger.warning("StatsCollect SSH failed: #{inspect(reason)}")
        :ok
    end
  end

  defp write_sample(server, output, now) do
    case parse(output, server, now) do
      {:ok, stats, raw_net, raw_disk} ->
        recorded_at = DateTime.truncate(now, :microsecond)

        {:ok, _} =
          Fleet.record_sample(server, %{
            bucket: "1m",
            recorded_at: recorded_at,
            stats: stats
          })

        {:ok, _} =
          Fleet.update_counters(server, %{
            last_net_counters: %{
              "captured_at" => DateTime.to_iso8601(recorded_at),
              "ifaces" => raw_net |> stringify_keys()
            },
            last_disk_counters: %{
              "captured_at" => DateTime.to_iso8601(recorded_at),
              "sectors_read" => raw_disk.sectors_read,
              "sectors_written" => raw_disk.sectors_written
            }
          })

        :ok

      {:error, reason} ->
        Logger.warning("StatsCollect parse failed: #{inspect(reason)}")
        :ok
    end
  end

  defp parse(output, server, now) do
    case split_combined(output) do
      %{top: top, free: free, df: df, net: net, io: io, load: load} ->
        parse_parts(top, free, df, net, io, load, server, now)

      _ ->
        {:error, :delimiters}
    end
  end

  defp parse_parts(top, free, df, net, io, load, server, now) do
    prev_net = decode_net_prev(server.last_net_counters)
    prev_disk = decode_disk_prev(server.last_disk_counters)

    net_result = Metrics.parse_net_dev(net, prev_net, now)
    disk_result = Metrics.parse_diskstats(io, prev_disk, now)

    cond do
      is_nil(net_result) ->
        {:error, :net_dev_parse}

      is_nil(disk_result) ->
        {:error, :diskstats_parse}

      true ->
        {:ok, build_stats(top, free, df, load, net_result, disk_result), net_result.raw,
         disk_result.raw}
    end
  end

  defp build_stats(top, free, df, load, net, disk) do
    mem_bytes = Metrics.parse_memory_bytes(free) || %{}
    disks = Metrics.parse_df_p(df)
    root = Enum.find(disks, &(&1.mount == "/")) || %{}
    load_avg = Metrics.parse_load_avg(load) || %{}

    %{
      "cpu" => Metrics.parse_cpu(top),
      "memory" => Metrics.parse_memory(free),
      "memory_used_mb" => Map.get(mem_bytes, :used_mb),
      "disk_root" => Map.get(root, :used_pct),
      "disk_used_gb" => Map.get(root, :used_gb),
      "disks" => Enum.map(disks, &stringify_disk/1),
      "rx_bytes_s" => net.rx_bytes_s,
      "tx_bytes_s" => net.tx_bytes_s,
      "io_r_bytes_s" => disk.read_bytes_s,
      "io_w_bytes_s" => disk.write_bytes_s,
      "load_1" => Map.get(load_avg, :load_1),
      "load_5" => Map.get(load_avg, :load_5),
      "load_15" => Map.get(load_avg, :load_15)
    }
  end

  defp stringify_disk(%{mount: m, used_pct: p, total_gb: t, used_gb: u}) do
    %{"mount" => m, "used_pct" => p, "total_gb" => t, "used_gb" => u}
  end

  defp split_combined(output) do
    parts = String.split(output, ~r/^__([A-Z]+)__$\n?/m, include_captures: true, trim: true)

    parts
    |> Enum.chunk_every(2)
    |> Enum.reduce(%{}, fn
      [marker, body], acc ->
        case Regex.run(~r/^__([A-Z]+)__/, marker) do
          [_, "TOP"] -> Map.put(acc, :top, body)
          [_, "FREE"] -> Map.put(acc, :free, body)
          [_, "DF"] -> Map.put(acc, :df, body)
          [_, "NET"] -> Map.put(acc, :net, body)
          [_, "IO"] -> Map.put(acc, :io, body)
          [_, "LOAD"] -> Map.put(acc, :load, body)
          _ -> acc
        end

      _, acc ->
        acc
    end)
  end

  defp decode_net_prev(nil), do: nil

  defp decode_net_prev(map) when is_map(map) do
    with {:ok, at} <- decode_captured_at(map),
         ifaces when is_map(ifaces) <- map["ifaces"] || Map.get(map, :ifaces) do
      %{
        captured_at: at,
        ifaces:
          Map.new(ifaces, fn {name, vals} ->
            {name, %{rx: vals["rx"] || vals[:rx] || 0, tx: vals["tx"] || vals[:tx] || 0}}
          end)
      }
    else
      _ -> nil
    end
  end

  defp decode_disk_prev(nil), do: nil

  defp decode_disk_prev(map) when is_map(map) do
    with {:ok, at} <- decode_captured_at(map) do
      %{
        captured_at: at,
        sectors_read: map["sectors_read"] || Map.get(map, :sectors_read, 0),
        sectors_written: map["sectors_written"] || Map.get(map, :sectors_written, 0)
      }
    end
  end

  defp decode_captured_at(map) do
    raw = map["captured_at"] || Map.get(map, :captured_at)

    cond do
      is_struct(raw, DateTime) ->
        {:ok, raw}

      is_binary(raw) ->
        DateTime.from_iso8601(raw)
        |> case do
          {:ok, dt, _} -> {:ok, dt}
          _ -> :error
        end

      true ->
        :error
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      value = if is_map(v), do: stringify_keys(v), else: v
      {key, value}
    end)
  end
end
