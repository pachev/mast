defmodule Mast.Logs.Systemd do
  @moduledoc """
  Log Source Adapter for systemd units, read via `journalctl`.
  """
  @behaviour Mast.Logs.Source

  @unit_regex ~r/^[A-Za-z0-9@._-]+(\.service)?$/

  @impl true
  def validate_target(target) when is_binary(target) do
    if Regex.match?(@unit_regex, target) do
      :ok
    else
      {:error, "must be a valid systemd unit name"}
    end
  end

  def validate_target(_), do: {:error, "must be a valid systemd unit name"}

  @impl true
  def stream_command(unit) when is_binary(unit) do
    "sudo -n journalctl -u #{unit} -f -n 200 --output=cat"
  end
end
