defmodule Mast.Logs.Source do
  @moduledoc """
  Behaviour for a Log Source Adapter. Each implementation knows how to
  validate a Log Target for its source kind and how to build the
  streaming shell command that tails it.

  Adapters know nothing about SSH. Callers feed the returned command
  string to `Mast.SSH.run_stream/4`.

  See ADR 0008.
  """

  @doc """
  Validates that `target` is a well-formed address for this Log Source.
  Returns `:ok` or `{:error, message}`. The message is shown to the
  Operator in changeset errors.
  """
  @callback validate_target(target :: String.t()) :: :ok | {:error, String.t()}

  @doc """
  Returns the shell command that tails `target`. Includes any required
  `sudo -n` prefix. Callers must `validate_target/1` first.
  """
  @callback stream_command(target :: String.t()) :: String.t()
end
