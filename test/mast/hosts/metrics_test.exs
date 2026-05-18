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
end
