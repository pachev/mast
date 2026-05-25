defmodule Mast.Patches.Runs do
  @moduledoc """
  Context for the last apply-updates run per server (`Mast.Patches.Run`).

  One row per server: `start_run/1` upserts over any prior run. The worker
  streams output through `append/2` (batched) and closes the run with
  `finish/3`. `get_for_server/1` lets a (re)mounting LiveView reattach.
  """
  import Ecto.Query, warn: false

  alias Mast.Patches.Run
  alias Mast.Repo

  @doc """
  Starts a run, replacing any existing row for the server. Returns the fresh
  `running` row with an empty log.
  """
  def start_run(attrs) do
    attrs = Map.merge(%{status: "running", log: "", exit_code: nil, error: nil}, attrs)

    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace, [:run_id, :scope, :package, :status, :exit_code, :log, :error, :updated_at]},
      conflict_target: :server_id
    )
  end

  @doc "Appends a batch of lines to the run log, joined by newlines. No-op on `[]`."
  def append(%Run{} = run, []), do: {:ok, run}

  def append(%Run{} = run, lines) when is_list(lines) do
    appended = Enum.join(lines, "\n")
    log = if run.log in [nil, ""], do: appended, else: run.log <> "\n" <> appended

    run
    |> Run.changeset(%{log: log})
    |> Repo.update()
  end

  @doc """
  Closes a run. `status` is `:done` or `:error`. Opts: `:exit_code`, `:error`.
  """
  def finish(%Run{} = run, status, opts \\ []) when status in [:done, :error] do
    attrs =
      %{status: Atom.to_string(status)}
      |> maybe_put(:exit_code, Keyword.get(opts, :exit_code))
      |> maybe_put(:error, Keyword.get(opts, :error))

    run
    |> Run.changeset(attrs)
    |> Repo.update()
  end

  @doc "Returns the last run for a server, or nil."
  def get_for_server(server_id) do
    Repo.get_by(Run, server_id: server_id)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
