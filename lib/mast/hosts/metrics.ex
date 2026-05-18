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
end
