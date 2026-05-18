defmodule Mast.Patches.Dnf do
  @moduledoc """
  Parser for `dnf check-update` output (Amazon Linux 2023, Fedora, Rocky, RHEL).

  `dnf check-update` exits with status 100 when updates are available and 0
  when there are none. Callers must treat exit 100 as success; this parser
  itself only knows about stdout shape.

  Output shape (one upgradable package per line):

      name.arch    version    repo

  The command may also append an `Obsoleting Packages` section after a
  blank line — those lines describe replacements rather than upgrades and
  are intentionally ignored.
  """

  @line_regex ~r/^([a-zA-Z0-9._+:-]+)\.([a-zA-Z0-9_]+)\s+(\S+)\s+(\S+)\s*$/

  @spec parse(String.t()) :: %{total: non_neg_integer(), updates: [map()]}
  def parse(output) when is_binary(output) do
    updates =
      output
      |> String.split("\n")
      |> Enum.reduce_while({:upgrades, []}, fn line, {section, acc} ->
        cond do
          section == :done ->
            {:halt, {:done, acc}}

          String.starts_with?(String.trim_leading(line), "Obsoleting Packages") ->
            {:halt, {:done, acc}}

          true ->
            {:cont, {section, parse_line(line, acc)}}
        end
      end)
      |> elem(1)
      |> Enum.reverse()

    %{total: length(updates), updates: updates}
  end

  defp parse_line(line, acc) do
    case Regex.run(@line_regex, line) do
      [_, package, arch, new_v, repo] ->
        [
          %{
            package: package,
            architecture: arch,
            new_version: new_v,
            repository: repo
          }
          | acc
        ]

      _ ->
        acc
    end
  end
end
