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
      user_dir: user_dir(),
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
      {:stdout, _} -> true
      _ -> false
    end)
    |> Enum.map_join("", fn {:stdout, data} -> data end)
  end

  defp render_output(_), do: ""

  # Erlang's :ssh scans user_dir for id_rsa, id_ed25519, etc. Operators with
  # non-standard key paths should set a custom user_dir via:
  #   config :mast, Mast.SSH.SSHKit, user_dir: "/path/to/dir/of/keys"
  # and put a copy or symlink of the key with a standard name inside it.
  # Per-server keys with passphrases will land in a Mast.PrivateKey schema
  # later (v0.x).
  defp user_dir do
    case Application.get_env(:mast, __MODULE__, [])[:user_dir] do
      nil -> String.to_charlist(Path.expand("~/.ssh"))
      dir -> String.to_charlist(Path.expand(dir))
    end
  end
end

