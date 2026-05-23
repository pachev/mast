defmodule Mast.Hosts.MetricsTest do
  use ExUnit.Case, async: true

  alias Mast.Hosts.Metrics

  describe "parse_cpu/1 (top -bn1)" do
    test "parses Ubuntu top header with %Cpu(s) line" do
      out = """
      top - 10:42:00 up  2:03,  1 user,  load average: 0.21, 0.34, 0.40
      Tasks: 145 total,   1 running, 144 sleeping,   0 stopped,   0 zombie
      %Cpu(s):  3.1 us,  1.2 sy,  0.0 ni, 94.5 id,  1.2 wa,  0.0 hi,  0.0 si,  0.0 st
      """

      # CPU usage = 100 - idle
      assert Metrics.parse_cpu(out) == 5.5
    end

    test "returns nil when no %Cpu(s) line present" do
      assert Metrics.parse_cpu("garbage output") == nil
    end
  end

  describe "parse_memory/1 (free -m)" do
    test "parses memory usage as percentage" do
      out = """
                     total        used        free      shared  buff/cache   available
      Mem:            7948        2240        3402         156        2305        5707
      Swap:           2048           0        2048
      """

      # used / total = 2240 / 7948 ≈ 28.18%
      assert_in_delta Metrics.parse_memory(out), 28.18, 0.1
    end

    test "returns nil for malformed output" do
      assert Metrics.parse_memory("") == nil
    end
  end

  describe "parse_memory_bytes/1 (free -m raw)" do
    test "returns total and used in MB" do
      out = """
                     total        used        free      shared  buff/cache   available
      Mem:            7948        2240        3402         156        2305        5707
      Swap:           2048           0        2048
      """

      assert Metrics.parse_memory_bytes(out) == %{total_mb: 7948, used_mb: 2240}
    end

    test "returns nil for malformed output" do
      assert Metrics.parse_memory_bytes("nope") == nil
    end
  end

  describe "parse_disk/1 (df -h /)" do
    test "extracts the use% column" do
      out = """
      Filesystem      Size  Used Avail Use% Mounted on
      /dev/sda1        50G   12G   36G  26% /
      """

      assert Metrics.parse_disk(out) == 26.0
    end

    test "tolerates extra header lines" do
      out = "Filesystem Size Used Avail Use% Mounted on\n/dev/root 50G 4G 46G 8% /\n"
      assert Metrics.parse_disk(out) == 8.0
    end

    test "returns nil when no Use% column found" do
      assert Metrics.parse_disk("nope") == nil
    end
  end

  describe "parse_disk_bytes/1 (df -h / raw)" do
    test "extracts total + used in GB from human-readable output" do
      out = """
      Filesystem      Size  Used Avail Use% Mounted on
      /dev/sda1        50G   12G   36G  26% /
      """

      assert Metrics.parse_disk_bytes(out) == %{total_gb: 50.0, used_gb: 12.0}
    end

    test "handles fractional sizes" do
      out = "Filesystem Size Used Avail Use% Mounted on\n/dev/root 1.5T 240G 1.2T 17% /\n"
      # 1.5T = 1536 GB, 240G stays.
      assert Metrics.parse_disk_bytes(out) == %{total_gb: 1536.0, used_gb: 240.0}
    end

    test "handles M-suffixed used on tiny filesystems" do
      out = "Filesystem Size Used Avail Use% Mounted on\n/dev/loop0 100M 50M 50M 50% /\n"
      result = Metrics.parse_disk_bytes(out)
      # 100 MiB = 100/1024 GiB ≈ 0.0977
      assert_in_delta result.total_gb, 0.0977, 0.001
      assert_in_delta result.used_gb, 0.0488, 0.001
    end

    test "returns nil when no size column found" do
      assert Metrics.parse_disk_bytes("nope") == nil
    end
  end

  describe "parse_load_avg/1 (/proc/loadavg)" do
    test "parses the three load averages from a standard line" do
      assert Metrics.parse_load_avg("0.42 0.55 0.61 2/123 12345\n") ==
               %{load_1: 0.42, load_5: 0.55, load_15: 0.61}
    end

    test "handles zeroed-out idle machines" do
      assert Metrics.parse_load_avg("0.00 0.00 0.00 1/100 999\n") ==
               %{load_1: 0.0, load_5: 0.0, load_15: 0.0}
    end

    test "tolerates missing trailing newline" do
      assert Metrics.parse_load_avg("1.20 0.80 0.40 1/1 1") ==
               %{load_1: 1.20, load_5: 0.80, load_15: 0.40}
    end

    test "returns nil for malformed input" do
      assert Metrics.parse_load_avg("nope") == nil
      assert Metrics.parse_load_avg("") == nil
    end
  end

  describe "parse_net_dev/2 (/proc/net/dev with delta)" do
    @fixture File.read!("test/support/fixtures/proc/net_dev.txt")

    test "returns zero rates and primes the raw cache when prev is nil" do
      r = Metrics.parse_net_dev(@fixture, nil)
      assert r.rx_bytes_s == 0.0
      assert r.tx_bytes_s == 0.0
      assert is_map(r.raw)
      assert r.raw["eth0"].rx > 0
      assert r.raw["eth0"].tx > 0
    end

    test "excludes loopback from totals" do
      r = Metrics.parse_net_dev(@fixture, nil)
      # eth0 rx in fixture is 669412285; lo is 3958040. raw must not include lo in totals.
      refute Map.has_key?(r.raw, "lo")
    end

    test "computes per-second deltas given prev captured 60s earlier" do
      now = DateTime.utc_now()
      prev_at = DateTime.add(now, -60, :second)

      prev = %{
        captured_at: prev_at,
        ifaces: %{"eth0" => %{rx: 669_425_513 - 60_000, tx: 8_587_456 - 6_000}}
      }

      r = Metrics.parse_net_dev(@fixture, prev, now)
      # 60_000 bytes over 60s = 1_000 bytes/s
      assert_in_delta r.rx_bytes_s, 1_000.0, 0.5
      assert_in_delta r.tx_bytes_s, 100.0, 0.5
    end

    test "clamps negative deltas to 0 on counter wraparound" do
      now = DateTime.utc_now()
      prev_at = DateTime.add(now, -60, :second)

      prev = %{
        captured_at: prev_at,
        ifaces: %{"eth0" => %{rx: 999_999_999_999, tx: 999_999_999_999}}
      }

      r = Metrics.parse_net_dev(@fixture, prev, now)
      assert r.rx_bytes_s == 0.0
      assert r.tx_bytes_s == 0.0
    end

    test "returns nil for unparseable input" do
      assert Metrics.parse_net_dev("nope", nil) == nil
    end
  end

  describe "parse_diskstats/2 (/proc/diskstats with delta)" do
    @fixture File.read!("test/support/fixtures/proc/diskstats.txt")

    test "returns zero rates and primes raw when prev is nil" do
      r = Metrics.parse_diskstats(@fixture, nil)
      assert r.read_bytes_s == 0.0
      assert r.write_bytes_s == 0.0
      assert is_map(r.raw)
      assert r.raw.sectors_read > 0
    end

    test "ignores loop and dm devices in totals" do
      r = Metrics.parse_diskstats(@fixture, nil)
      # nvme0n1 root + partitions contribute; loop and dm are excluded.
      # nvme0n1 has 298_166_048 sectors read (col 6).
      assert r.raw.sectors_read >= 298_166_048
    end

    test "computes bytes/s as (delta sectors * 512) / elapsed" do
      now = DateTime.utc_now()
      prev_at = DateTime.add(now, -60, :second)
      # 1024 sectors over 60s = 1024*512/60 ≈ 8738.13 bytes/s
      current_r = parse_raw_sectors_read(@fixture)
      current_w = parse_raw_sectors_written(@fixture)

      prev = %{
        captured_at: prev_at,
        sectors_read: current_r - 1024,
        sectors_written: current_w - 2048
      }

      r = Metrics.parse_diskstats(@fixture, prev, now)
      assert_in_delta r.read_bytes_s, 1024 * 512 / 60, 1.0
      assert_in_delta r.write_bytes_s, 2048 * 512 / 60, 1.0
    end

    defp parse_raw_sectors_read(fixture),
      do: Metrics.parse_diskstats(fixture, nil).raw.sectors_read

    defp parse_raw_sectors_written(fixture),
      do: Metrics.parse_diskstats(fixture, nil).raw.sectors_written
  end

  describe "parse_df_p/1 (df -P all mounts)" do
    @fixture File.read!("test/support/fixtures/proc/df_p.txt")

    test "returns one entry per real mount" do
      entries = Metrics.parse_df_p(@fixture)
      assert is_list(entries)
      assert Enum.any?(entries, &(&1.mount == "/"))
    end

    test "filters out tmpfs / udev / virtual fs" do
      entries = Metrics.parse_df_p(@fixture)
      mounts = Enum.map(entries, & &1.mount)
      refute "/dev" in mounts
      refute "/dev/tty" in mounts
      refute "/dev/shm" in mounts
      refute "/run" in mounts
    end

    test "extracts used_pct, total_gb, used_gb for root" do
      entries = Metrics.parse_df_p(@fixture)
      root = Enum.find(entries, &(&1.mount == "/"))
      assert root.used_pct == 24.0
      # 12278920 1024-blocks ≈ 11.71 GB
      assert_in_delta root.total_gb, 11.71, 0.05
      assert_in_delta root.used_gb, 2.66, 0.05
    end

    test "returns empty list for unparseable input" do
      assert Metrics.parse_df_p("nope\n") == []
    end
  end
end
