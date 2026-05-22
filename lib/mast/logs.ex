defmodule Mast.Logs do
  @moduledoc """
  Dispatcher for Log Source adapters. See ADR 0008 and `Mast.Logs.Source`.

  Adapters are wired by Log Source string:

    * `"systemd"` → `Mast.Logs.Systemd`
    * `"file"` → `Mast.Logs.File`

  The `"none"` source has no adapter; callers must short-circuit.
  """

  @adapters %{
    "systemd" => Mast.Logs.Systemd,
    "file" => Mast.Logs.File
  }

  @doc """
  Validates a `log_target` against the adapter for `log_source`. Returns
  `:ok` or `{:error, message}`.
  """
  def validate_target(source, target) when is_binary(source) and is_binary(target) do
    case Map.fetch(@adapters, source) do
      {:ok, mod} -> mod.validate_target(target)
      :error -> {:error, "unknown log source"}
    end
  end

  @doc """
  Builds the streaming shell command for a `(source, target)` pair.
  Raises when `source` is unknown or `target` invalid; callers should
  validate beforehand.
  """
  def stream_command(source, target) when is_binary(source) and is_binary(target) do
    mod = Map.fetch!(@adapters, source)
    :ok = mod.validate_target(target)
    mod.stream_command(target)
  end

  @doc "Returns the list of known log source strings (excludes \"none\")."
  def sources, do: Map.keys(@adapters)
end
