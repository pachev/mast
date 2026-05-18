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
  alias SSHKit.SSH.Connection

  @impl true
  def run(%Server{} = server, command) when is_binary(command) do
    server = Mast.SSH.preload_key(server)
    opts = connect_opts(server, 10_000)
    context = SSHKit.context({server.host, opts})

    case SSHKit.run(context, command) do
      [{:ok, output, 0}] ->
        {:ok, render_output(output)}

      [{:ok, output, exit}] ->
        {:error, {:non_zero_exit, exit, render_output(output, include_stderr: true)}}

      [{:error, reason}] ->
        {:error, reason}

      other ->
        {:error, {:unexpected, other}}
    end
  end

  @impl true
  def run_stream(%Server{} = server, command, reducer, acc) when is_binary(command) do
    server = Mast.SSH.preload_key(server)
    opts = connect_opts(server, :infinity)

    case Connection.open(server.host, opts) do
      {:ok, conn} ->
        # Track {caller_acc, exit_code | nil} through the loop so we can emit
        # a final {:exit, code} event after closure.
        initial = {acc, nil}

        result =
          SSHKit.SSH.run(conn, command,
            acc: {:cont, initial},
            fun: stream_fun(reducer),
            timeout: :infinity
          )

        :ok = Connection.close(conn)

        case result do
          {final_acc, code} when is_integer(code) -> reducer.({:exit, code}, final_acc)
          {final_acc, nil} -> reducer.({:exit, -1}, final_acc)
          {:error, reason} -> reducer.({:error, reason}, acc)
          other -> reducer.({:error, {:unexpected, other}}, acc)
        end

      {:error, reason} ->
        reducer.({:error, reason}, acc)
    end
  end

  defp stream_fun(reducer) do
    fn message, {user_acc, code} ->
      next =
        case message do
          {:data, _, 0, data} -> {reducer.({:line, :stdout, data}, user_acc), code}
          {:data, _, 1, data} -> {reducer.({:line, :stderr, data}, user_acc), code}
          {:exit_status, _, c} -> {user_acc, c}
          _ -> {user_acc, code}
        end

      {:cont, next}
    end
  end

  defp connect_opts(%Server{port: port, user: user} = server, timeout) do
    base = [
      port: port,
      user: user,
      silently_accept_hosts: true,
      user_interaction: false,
      timeout: timeout
    ]

    case key_pem(server) do
      nil ->
        # Fallback: legacy priv/ssh user_dir scan, kept for the bootstrap case
        # where no DB-stored key exists yet. Will be removed once we have a
        # default-key concept.
        Keyword.put(base, :user_dir, user_dir())

      pem when is_binary(pem) ->
        Keyword.put(base, :key_cb, {Mast.SSH.KeyCb, [pem: pem]})
    end
  end

  defp key_pem(%Server{private_key: %Mast.Keys.PrivateKey{} = key}) do
    case Mast.Keys.material(key) do
      {:ok, pem} -> pem
      _ -> nil
    end
  end

  defp key_pem(_), do: nil

  defp render_output(output, opts \\ [])

  defp render_output(output, opts) when is_list(output) do
    include_stderr = Keyword.get(opts, :include_stderr, false)

    output
    |> Enum.filter(fn
      {:stdout, _} -> true
      {:stderr, _} -> include_stderr
      _ -> false
    end)
    |> Enum.map_join("", fn
      {:stdout, data} -> data
      {:stderr, data} -> data
    end)
  end

  defp render_output(_, _), do: ""

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
