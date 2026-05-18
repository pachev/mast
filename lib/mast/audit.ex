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

  @default_page_size 50
  @max_page_size 200

  @doc """
  Returns one cursor-paged slice of audit events, newest first.

  Opts:
    * `:limit` — page size, capped at #{@max_page_size} (default #{@default_page_size})
    * `:cursor` — opaque string returned as `next_cursor` from a prior call
    * `:event_type` — exact match, empty string treated as no filter
    * `:subject_type` — exact match, empty string treated as no filter
    * `:query` — case-insensitive substring match against `event_type`

  Returns `%{events: [Event.t()], next_cursor: String.t() | nil}`. The
  cursor is opaque to callers; pass it back verbatim.
  """
  def list_page(opts \\ []) when is_list(opts) do
    limit =
      opts
      |> Keyword.get(:limit, @default_page_size)
      |> clamp_limit()

    query =
      Event
      |> order_by([e], desc: e.inserted_at, desc: e.id)
      |> limit(^(limit + 1))
      |> apply_filter(:event_type, Keyword.get(opts, :event_type))
      |> apply_filter(:subject_type, Keyword.get(opts, :subject_type))
      |> apply_query(Keyword.get(opts, :query))
      |> apply_cursor(Keyword.get(opts, :cursor))

    rows = Repo.all(query)

    if length(rows) > limit do
      page = Enum.take(rows, limit)
      %{events: page, next_cursor: encode_cursor(List.last(page))}
    else
      %{events: rows, next_cursor: nil}
    end
  end

  defp clamp_limit(n) when is_integer(n) and n > 0, do: min(n, @max_page_size)
  defp clamp_limit(_), do: @default_page_size

  defp apply_filter(query, _field, nil), do: query
  defp apply_filter(query, _field, ""), do: query
  defp apply_filter(query, :event_type, v), do: where(query, [e], e.event_type == ^v)
  defp apply_filter(query, :subject_type, v), do: where(query, [e], e.subject_type == ^v)

  defp apply_query(query, nil), do: query
  defp apply_query(query, ""), do: query

  defp apply_query(query, q) when is_binary(q) do
    pattern = "%" <> escape_like(q) <> "%"
    where(query, [e], ilike(e.event_type, ^pattern))
  end

  defp escape_like(s), do: String.replace(s, ["\\", "%", "_"], &("\\" <> &1))

  defp apply_cursor(query, nil), do: query
  defp apply_cursor(query, ""), do: query

  defp apply_cursor(query, cursor) when is_binary(cursor) do
    case decode_cursor(cursor) do
      {:ok, ts, id} ->
        where(
          query,
          [e],
          e.inserted_at < ^ts or (e.inserted_at == ^ts and e.id < ^id)
        )

      :error ->
        query
    end
  end

  defp encode_cursor(%Event{inserted_at: ts, id: id}) do
    Base.url_encode64("#{DateTime.to_iso8601(ts)}|#{id}", padding: false)
  end

  defp decode_cursor(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [iso, id_str] <- String.split(raw, "|", parts: 2),
         {:ok, ts, _} <- DateTime.from_iso8601(iso),
         {id, ""} <- Integer.parse(id_str) do
      {:ok, ts, id}
    else
      _ -> :error
    end
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
