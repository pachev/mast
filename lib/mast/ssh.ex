defmodule Mast.SSH do
  @moduledoc """
  Thin dispatcher to the configured SSH executor.

  Two callbacks:

  - `run/2` blocks until the command finishes, returning `{:ok, stdout}` or
    `{:error, reason}`. Used for short commands (parsers, health checks).

  - `run_stream/4` runs the command and yields events as they arrive, calling
    `reducer.(event, acc)` for each. Events are `{:line, :stdout | :stderr,
    String.t()} | {:exit, integer()} | {:error, term()}`. Used for long
    running operations (apt upgrade) where we want to surface output live.

  In production the default impl is `Mast.SSH.SSHKit`. In tests it's
  `Mast.SSH.Stub` (see `config/test.exs`). See ADR 0003 for rationale.
  """

  alias Mast.Fleet.Server

  @type result :: {:ok, String.t()} | {:error, term()}
  @type stream_event ::
          {:line, :stdout | :stderr, String.t()}
          | {:exit, integer()}
          | {:error, term()}

  @callback run(Server.t(), String.t()) :: result()
  @callback run_stream(Server.t(), String.t(), (stream_event(), acc -> acc), acc) :: acc
            when acc: any()

  @spec run(Server.t(), String.t()) :: result()
  def run(%Server{} = server, command) when is_binary(command) do
    impl().run(server, command)
  end

  @spec run_stream(Server.t(), String.t(), (stream_event(), acc -> acc), acc) :: acc
        when acc: any()
  def run_stream(%Server{} = server, command, reducer, acc)
      when is_binary(command) and is_function(reducer, 2) do
    impl().run_stream(server, command, reducer, acc)
  end

  @doc """
  Ensures `server.private_key` is loaded. Workers grab a server by id and
  hand it to `run/2`/`run_stream/4`; the SSHKit impl needs the key body
  to dial. This helper centralises the preload so each caller doesn't
  forget — and the no-key path is a no-op, so it's safe to call always.
  """
  @spec preload_key(Server.t()) :: Server.t()
  def preload_key(%Server{private_key_id: nil} = server), do: server

  def preload_key(%Server{private_key: %Mast.Keys.PrivateKey{}} = server), do: server

  def preload_key(%Server{} = server) do
    Mast.Repo.preload(server, :private_key)
  end

  defp impl, do: Application.get_env(:mast, :ssh, Mast.SSH.SSHKit)
end
