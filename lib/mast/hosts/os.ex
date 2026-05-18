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

  def package_manager(id) do
    type =
      case id do
        i when i in ~w(manjaro manjaro-arm endeavouros) -> "arch"
        i when i in ~w(pop linuxmint zorin) -> "ubuntu"
        "fedora-asahi-remix" -> "fedora"
        other -> other
      end

    case type do
      t when t in ~w(ubuntu debian raspbian) -> "apt"
      t when t in ~w(fedora rocky rhel ol amzn centos almalinux) -> "dnf"
      "arch" -> "pacman"
      "alpine" -> "apk"
      t when t in ~w(sles opensuse-leap opensuse-tumbleweed) -> "zypper"
      _ -> nil
    end
  end
end
