defmodule Mast.SSH do
  @moduledoc """
  Thin dispatcher to the configured SSH executor.

  In production the default impl is `Mast.SSH.SSHKit`. In tests it's
  `Mast.SSH.Stub` (see `config/test.exs`). See ADR 0003 for rationale.
  """

  alias Mast.Fleet.Server

  @type result :: {:ok, String.t()} | {:error, term()}

  @callback run(Server.t(), String.t()) :: result()

  @spec run(Server.t(), String.t()) :: result()
  def run(%Server{} = server, command) when is_binary(command) do
    impl().run(server, command)
  end

  defp impl, do: Application.get_env(:mast, :ssh, Mast.SSH.SSHKit)
end
