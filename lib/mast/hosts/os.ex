defmodule Mast.Hosts.OS do
  @moduledoc """
  Parses `/etc/os-release` and maps the OS to a package manager.
  Mirrors Coolify's `CheckUpdates::handle` normalisation.
  """

  @doc """
  Parses os-release output into `%{os_id: String.t() | nil, package_manager: String.t() | nil}`.
  """
  @spec parse(String.t()) :: %{os_id: String.t() | nil, package_manager: String.t() | nil}
  def parse(output) when is_binary(output) do
    id =
      output
      |> String.split("\n", trim: true)
      |> Enum.find_value(fn line ->
        case String.split(line, "=", parts: 2) do
          ["ID", v] -> String.trim(v, "\"")
          _ -> nil
        end
      end)

    %{os_id: id, package_manager: package_manager(id)}
  end

  @doc "Maps OS id to package manager. Returns nil for unsupported."
  @spec package_manager(String.t() | nil) :: String.t() | nil
  def package_manager(nil), do: nil

  @aliases %{
    "manjaro" => "arch",
    "manjaro-arm" => "arch",
    "endeavouros" => "arch",
    "pop" => "ubuntu",
    "linuxmint" => "ubuntu",
    "zorin" => "ubuntu",
    "fedora-asahi-remix" => "fedora"
  }

  @managers %{
    "ubuntu" => "apt",
    "debian" => "apt",
    "raspbian" => "apt",
    "fedora" => "dnf",
    "rocky" => "dnf",
    "rhel" => "dnf",
    "ol" => "dnf",
    "amzn" => "dnf",
    "centos" => "dnf",
    "almalinux" => "dnf",
    "arch" => "pacman",
    "alpine" => "apk",
    "sles" => "zypper",
    "opensuse-leap" => "zypper",
    "opensuse-tumbleweed" => "zypper"
  }

  def package_manager(id) do
    Map.get(@managers, Map.get(@aliases, id, id))
  end
end
