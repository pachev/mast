defmodule Mast.Patches.Apt do
  @moduledoc """
  Parser for `apt list --upgradable` output, plus package-name validation.

  Mirrors Coolify's `CheckUpdates::parseAptOutput`. We always run the remote
  command with `LANG=C` so the locale-translated header lines never reach this
  parser; the parser only recognises the English bracketed form, by design.
  """

  @line_regex ~r/^(.+?)\/(\S+)\s+(\S+)\s+(\S+)\s+\[upgradable from: (.+?)\]/

  @package_regex ~r/^[a-zA-Z0-9._+:-]+$/

  @doc """
  Parses stdout from `LANG=C apt list --upgradable 2>/dev/null`.

  Returns `%{total: integer, updates: [%{...}]}` with one map per upgradable
  package.
  """
  @spec parse(String.t()) :: %{total: non_neg_integer(), updates: [map()]}
  def parse(output) when is_binary(output) do
    updates =
      output
      |> String.split("\n", trim: true)
      |> Enum.flat_map(&parse_line/1)

    %{total: length(updates), updates: updates}
  end

  defp parse_line("Listing..." <> _), do: []

  defp parse_line(line) do
    case Regex.run(@line_regex, line) do
      [_, package, repo, new_v, arch, current] ->
        [
          %{
            package: package,
            repository: repo,
            new_version: new_v,
            architecture: arch,
            current_version: current
          }
        ]

      _ ->
        []
    end
  end

  @doc """
  True if `name` only contains characters that are valid in package names
  across apt/dnf/pacman/zypper. Reject *before* shell-escaping — defense in
  depth.
  """
  @spec safe_package_name?(term()) :: boolean()
  def safe_package_name?(name) when is_binary(name) and name != "" do
    Regex.match?(@package_regex, name)
  end

  def safe_package_name?(_), do: false
end
