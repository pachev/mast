defmodule Mast.Logs.File do
  @moduledoc """
  Log Source Adapter for plain files, read via `tail -F`.

  Globs are not supported in v1: `tail -F` already follows rotation, so
  one path covers the common case. Multi-file support arrives if a real
  Operator files an issue for it.
  """
  @behaviour Mast.Logs.Source

  @forbidden_chars [
    "*",
    "?",
    "[",
    "]",
    "{",
    "}",
    "(",
    ")",
    ";",
    "&",
    "|",
    "<",
    ">",
    "$",
    "`",
    "\\",
    "'",
    "\"",
    "\n",
    "\t",
    "\r"
  ]

  @impl true
  def validate_target(target) when is_binary(target) do
    cond do
      not String.starts_with?(target, "/") ->
        {:error, "must be an absolute path"}

      String.contains?(target, "..") ->
        {:error, "must not contain '..' segments"}

      Enum.any?(@forbidden_chars, &String.contains?(target, &1)) ->
        {:error, "must not contain shell metacharacters or whitespace"}

      String.contains?(target, " ") ->
        {:error, "must not contain whitespace"}

      true ->
        :ok
    end
  end

  def validate_target(_), do: {:error, "must be an absolute path"}

  @impl true
  def stream_command(path) when is_binary(path) do
    "sudo -n tail -n 200 -F #{path}"
  end
end
