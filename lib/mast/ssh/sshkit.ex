defmodule Mast.SSH.SSHKit do
  @moduledoc """
  Production SSH executor. Wraps the `sshkit` hex package on top of Erlang's
  `:ssh`.

  Connection caching: SSHKit opens a connection on first use within the
  calling process. For a multi-host worker that loops over servers, this
  yields connection reuse without us managing ControlMaster sockets the way
  Coolify does in Laravel.

  Authentication: relies on the operator's `~/.ssh/config` and ssh-agent for
  v0.1. Per-server private-key storage is a v0.2 concern (see ADR 0001).
  """
  @behaviour Mast.SSH

  alias Mast.Fleet.Server

  @impl true
  def run(%Server{host: host, user: user, port: port}, command) when is_binary(command) do
    opts = [
      port: port,
      user: user,
      user_dir: String.to_charlist(Path.expand("~/.ssh")),
      silently_accept_hosts: true,
      user_interaction: false,
      timeout: 10_000
    ]

    context = SSHKit.context({host, opts})

    case SSHKit.run(context, command) do
      [{:ok, output, 0}] ->
        {:ok, render_output(output)}

      [{:ok, output, exit}] ->
        {:error, {:non_zero_exit, exit, render_output(output)}}

      [{:error, reason}] ->
        {:error, reason}

      other ->
        {:error, {:unexpected, other}}
    end
  end

  defp render_output(output) when is_list(output) do
    output
    |> Enum.filter(fn
      {:stdout, _, _} -> true
      _ -> false
    end)
    |> Enum.map_join("", fn {:stdout, data, _} -> data end)
  end

  defp render_output(_), do: ""
end
