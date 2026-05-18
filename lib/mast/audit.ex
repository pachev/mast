defmodule Mast.Audit do
  @moduledoc """
  Audit logging. Append-only. Every meaningful action in Mast writes one
  of these rows.

  Contract for `log/1`: never raises, never silently fails. On insert
  failure it returns `{:error, changeset}` AND emits a `Logger.error`.
  Callers decide whether to abort the surrounding operation.

  Most callers should use `multi_log/3` so audit and business operations
  commit atomically.

  See ADR-0007 (when written) and `docs/issues/3` for the rationale.
  """
  require Logger
  import Ecto.Query

  alias Ecto.Multi
  alias Mast.Audit.Event
  alias Mast.Repo

  @doc """
  Logs a single audit event.

  Returns `{:ok, %Event{}}` on success, `{:error, changeset}` on failure.
  Logs the changeset error before returning so the failure is visible
  even when the caller swallows the tuple.
  """
  def log(attrs) when is_map(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, event} ->
        {:ok, event}

      {:error, changeset} = error ->
        Logger.error("Audit.log failed: #{inspect(changeset.errors)}")
        error
    end
  end

  @doc """
  Inserts an audit event step into an `Ecto.Multi`. Use this to commit an
  audit record alongside a business operation so they share a transaction.

  `attrs` may be a map or a 1-arity function receiving the changes map
  from prior multi steps (matches `Ecto.Multi.run/3` semantics).
  """
  def multi_log(%Multi{} = multi, name, attrs) when is_map(attrs) do
    Multi.insert(multi, name, Event.changeset(%Event{}, attrs))
  end

  def multi_log(%Multi{} = multi, name, fun) when is_function(fun, 1) do
    Multi.run(multi, name, fn repo, changes ->
      attrs = fun.(changes)

      %Event{}
      |> Event.changeset(attrs)
      |> repo.insert()
    end)
  end

  @doc "Returns the most recent audit events, newest first."
  def list_recent(limit \\ 50) when is_integer(limit) and limit > 0 do
    Event
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Returns audit events for a single (subject_type, subject_id), newest first."
  def list_for_subject(subject_type, subject_id, limit \\ 20)
      when is_binary(subject_type) and is_integer(subject_id) and is_integer(limit) and limit > 0 do
    Event
    |> where([e], e.subject_type == ^subject_type and e.subject_id == ^subject_id)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
