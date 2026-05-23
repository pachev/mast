defmodule Mast.Hosts.Metrics do
  @moduledoc """
  Pure parsers for host-level metrics commands. Inputs are stdout from
  `top`, `free`, and `df`; outputs are floats (percentages) or `nil`
  when a line couldn't be parsed.

  Workers compose these with `Mast.SSH.run/2`.
  """

  @doc """
  Parses `top -bn1 | head -3` output.

  Returns CPU usage as `100 - idle%`. The `%Cpu(s)` line looks like:

      %Cpu(s):  3.1 us,  1.2 sy,  0.0 ni, 94.5 id,  1.2 wa,  0.0 hi,  0.0 si,  0.0 st
  """
  @spec parse_cpu(String.t()) :: float() | nil
  def parse_cpu(output) when is_binary(output) do
    case Regex.run(~r/%Cpu\(s\):.*?([\d.]+)\s*id/, output) do
      [_, idle] ->
        case Float.parse(idle) do
          {n, _} -> Float.round(100.0 - n, 1)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Parses `free -m` output and returns used-memory percentage.

  The `Mem:` line:

      Mem:   total   used   free   shared   buff/cache   available
  """
  @spec parse_memory(String.t()) :: float() | nil
  def parse_memory(output) when is_binary(output) do
    with [_, total_s, used_s] <- Regex.run(~r/Mem:\s+(\d+)\s+(\d+)/, output),
         {total, _} when total > 0 <- Integer.parse(total_s),
         {used, _} <- Integer.parse(used_s) do
      Float.round(used / total * 100, 2)
    else
      _ -> nil
    end
  end

  @doc """
  Parses `free -m` output and returns total/used in MB.
  """
  @spec parse_memory_bytes(String.t()) :: %{total_mb: integer(), used_mb: integer()} | nil
  def parse_memory_bytes(output) when is_binary(output) do
    case Regex.run(~r/Mem:\s+(\d+)\s+(\d+)/, output) do
      [_, total_s, used_s] ->
        with {total, _} when total > 0 <- Integer.parse(total_s),
             {used, _} <- Integer.parse(used_s) do
          %{total_mb: total, used_mb: used}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Parses `df -h /` output. Returns the Use% column for the root filesystem.
  """
  @spec parse_disk(String.t()) :: float() | nil
  def parse_disk(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.find_value(fn line ->
      case Regex.run(~r/\s(\d+)%\s/, line) do
        [_, pct] ->
          {n, _} = Float.parse(pct)
          n

        _ ->
          nil
      end
    end)
  end

  @doc """
  Parses `df -h /` output. Returns total + used in GB for the root
  filesystem. Suffixes K/M/G/T are normalised to GB.
  """
  @spec parse_disk_bytes(String.t()) :: %{total_gb: float(), used_gb: float()} | nil
  def parse_disk_bytes(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.find_value(fn line ->
      case Regex.run(~r/\S+\s+([\d.]+[KMGTP]?)\s+([\d.]+[KMGTP]?)\s+\S+\s+\d+%\s+/, line) do
        [_, size_s, used_s] ->
          %{total_gb: size_to_gb(size_s), used_gb: size_to_gb(used_s)}

        _ ->
          nil
      end
    end)
  end

  defp size_to_gb(s) do
    {n, suffix} = Float.parse(s)

    case suffix do
      "K" -> Float.round(n / 1_048_576, 4)
      "M" -> Float.round(n / 1024, 4)
      "G" -> Float.round(n, 4)
      "T" -> Float.round(n * 1024, 4)
      "P" -> Float.round(n * 1_048_576, 4)
      _ -> Float.round(n, 4)
    end
  end

  @doc """
  Parses `/proc/loadavg`. The line is five whitespace-separated fields:

      0.42 0.55 0.61 2/123 12345

  Only the first three (1/5/15 minute averages) are returned.
  """
  @spec parse_load_avg(String.t()) :: %{load_1: float(), load_5: float(), load_15: float()} | nil
  def parse_load_avg(output) when is_binary(output) do
    case output |> String.split() |> Enum.take(3) do
      [a, b, c] ->
        with {l1, _} <- Float.parse(a),
             {l5, _} <- Float.parse(b),
             {l15, _} <- Float.parse(c) do
          %{load_1: l1, load_5: l5, load_15: l15}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Parses `/proc/net/dev` and computes per-second bandwidth rates against a
  previous sample.

  `prev` is the cached value from the last collect tick or `nil` on the
  first sample. Shape: `%{captured_at: DateTime.t(), ifaces: %{name => %{rx,
  tx}}}`. Loopback is excluded from totals. Returns rates of `0.0` when
  `prev` is `nil` (first sample primes the cache).

  Counter wraparound (current < prev) clamps to 0.
  """
  @spec parse_net_dev(String.t(), map() | nil, DateTime.t()) ::
          %{rx_bytes_s: float(), tx_bytes_s: float(), raw: map()} | nil
  def parse_net_dev(output, prev, now \\ nil)

  def parse_net_dev(output, prev, now) when is_binary(output) do
    case parse_net_dev_ifaces(output) do
      ifaces when map_size(ifaces) > 0 ->
        rx_total = ifaces |> Map.values() |> Enum.reduce(0, &(&1.rx + &2))
        tx_total = ifaces |> Map.values() |> Enum.reduce(0, &(&1.tx + &2))

        {rx_s, tx_s} = compute_net_rates(prev, ifaces, rx_total, tx_total, now)

        %{rx_bytes_s: rx_s, tx_bytes_s: tx_s, raw: ifaces}

      _ ->
        nil
    end
  end

  defp parse_net_dev_ifaces(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^\s*([^:\s]+):\s*(\d+)(?:\s+\d+){7}\s+(\d+)/, line) do
        [_, name, rx, tx] when name != "lo" ->
          {r, _} = Integer.parse(rx)
          {t, _} = Integer.parse(tx)
          [{name, %{rx: r, tx: t}}]

        _ ->
          []
      end
    end)
    |> Map.new()
  end

  defp compute_net_rates(nil, _ifaces, _rx, _tx, _now), do: {0.0, 0.0}

  defp compute_net_rates(prev, _ifaces, rx_total, tx_total, now) do
    now = now || DateTime.utc_now()
    elapsed = DateTime.diff(now, prev.captured_at, :second)

    if elapsed <= 0 do
      {0.0, 0.0}
    else
      prev_ifaces = Map.get(prev, :ifaces) || Map.get(prev, "ifaces") || %{}
      prev_rx = prev_ifaces |> Enum.reduce(0, fn {_, v}, acc -> acc + counter_get(v, :rx) end)
      prev_tx = prev_ifaces |> Enum.reduce(0, fn {_, v}, acc -> acc + counter_get(v, :tx) end)

      {clamp_rate(rx_total - prev_rx, elapsed), clamp_rate(tx_total - prev_tx, elapsed)}
    end
  end

  defp counter_get(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || 0
  end

  defp clamp_rate(delta, _elapsed) when delta < 0, do: 0.0
  defp clamp_rate(delta, elapsed), do: Float.round(delta / elapsed, 2)

  @doc """
  Parses `/proc/diskstats` and computes per-second I/O byte rates against a
  previous sample.

  Filters out loop and dm devices; sums sectors read and sectors written
  across physical block devices. Sector size is the kernel constant of 512
  bytes. `prev` shape: `%{captured_at, sectors_read, sectors_written}` or
  `nil` for first sample.
  """
  @spec parse_diskstats(String.t(), map() | nil, DateTime.t()) ::
          %{read_bytes_s: float(), write_bytes_s: float(), raw: map()} | nil
  def parse_diskstats(output, prev, now \\ nil)

  def parse_diskstats(output, prev, now) when is_binary(output) do
    case parse_diskstats_totals(output) do
      nil ->
        nil

      {sectors_read, sectors_written} ->
        {r_s, w_s} =
          compute_disk_rates(prev, sectors_read, sectors_written, now)

        %{
          read_bytes_s: r_s,
          write_bytes_s: w_s,
          raw: %{sectors_read: sectors_read, sectors_written: sectors_written}
        }
    end
  end

  defp parse_diskstats_totals(output) do
    lines =
      output
      |> String.split("\n", trim: true)
      |> Enum.flat_map(&parse_diskstats_line/1)

    if lines == [] do
      nil
    else
      Enum.reduce(lines, {0, 0}, fn {r, w}, {ra, wa} -> {ra + r, wa + w} end)
    end
  end

  # Columns (1-indexed): 1 major, 2 minor, 3 name, 4 reads, 5 reads merged,
  # 6 sectors read, 7 ms reading, 8 writes, 9 writes merged, 10 sectors
  # written, ...
  defp parse_diskstats_line(line) do
    case String.split(line) do
      [_maj, _min, name | rest] ->
        cond do
          virtual_block?(name) -> []
          length(rest) < 7 -> []
          true -> parse_diskstats_fields(name, rest)
        end

      _ ->
        []
    end
  end

  defp parse_diskstats_fields(_name, rest) do
    sectors_read = rest |> Enum.at(2) |> safe_int()
    sectors_written = rest |> Enum.at(6) |> safe_int()
    [{sectors_read, sectors_written}]
  end

  defp safe_int(nil), do: 0

  defp safe_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      _ -> 0
    end
  end

  # Skip virtual / aggregated devices: loop, dm-*, partition numbers (e.g.
  # nvme0n1p1, sda1) are also skipped to avoid double-counting against the
  # parent block device.
  defp virtual_block?(name) do
    String.starts_with?(name, "loop") or
      String.starts_with?(name, "ram") or
      String.starts_with?(name, "dm-") or
      String.starts_with?(name, "sr") or
      partition?(name)
  end

  defp partition?(name) do
    case Regex.run(~r/^(?:sd[a-z]+|hd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme\d+n\d+p)(\d+)$/, name) do
      [_, _] -> true
      _ -> false
    end
  end

  defp compute_disk_rates(nil, _r, _w, _now), do: {0.0, 0.0}

  defp compute_disk_rates(prev, sectors_read, sectors_written, now) do
    now = now || DateTime.utc_now()
    elapsed = DateTime.diff(now, prev.captured_at, :second)

    if elapsed <= 0 do
      {0.0, 0.0}
    else
      prev_r = Map.get(prev, :sectors_read, 0)
      prev_w = Map.get(prev, :sectors_written, 0)

      {
        clamp_rate((sectors_read - prev_r) * 512, elapsed),
        clamp_rate((sectors_written - prev_w) * 512, elapsed)
      }
    end
  end

  @virtual_fs ~w(tmpfs devtmpfs squashfs overlay aufs proc sysfs cgroup cgroup2 nsfs none udev)

  @doc """
  Parses `df -P` output (POSIX one-line-per-fs) and returns one entry per
  real mounted filesystem. Virtual filesystems (tmpfs, devtmpfs, etc.) are
  filtered out.

  1024-blocks are converted to GB (decimal: 1e9 bytes), matching how disk
  capacity is conventionally reported.
  """
  @spec parse_df_p(String.t()) :: [
          %{mount: String.t(), used_pct: float(), total_gb: float(), used_gb: float()}
        ]
  def parse_df_p(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_df_p_line/1)
  end

  defp parse_df_p_line(line) do
    case String.split(line) do
      [fs, blocks_s, used_s, _avail_s, pct_s, mount | _] ->
        cond do
          fs == "Filesystem" -> []
          virtual_fs?(fs) -> []
          true -> df_entry(blocks_s, used_s, pct_s, mount)
        end

      _ ->
        []
    end
  end

  defp virtual_fs?(fs) do
    Enum.any?(@virtual_fs, &(fs == &1)) or
      String.starts_with?(fs, "tmpfs") or
      fs == "none" or
      fs == "udev"
  end

  defp df_entry(blocks_s, used_s, pct_s, mount) do
    with {blocks, _} <- Integer.parse(blocks_s),
         {used, _} <- Integer.parse(used_s),
         {pct, _} <- Integer.parse(String.trim_trailing(pct_s, "%")) do
      # 1024-byte blocks -> GiB (1024^3). Matches parse_disk_bytes/1.
      total_gb = Float.round(blocks / 1_048_576, 2)
      used_gb = Float.round(used / 1_048_576, 2)
      [%{mount: mount, used_pct: pct * 1.0, total_gb: total_gb, used_gb: used_gb}]
    else
      _ -> []
    end
  end
end
