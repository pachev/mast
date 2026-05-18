defmodule Mast.Audit.Event do
  @moduledoc """
  Audit event schema. Append-only. The table has no `updated_at` because
  rows are never modified after insert.

  `actor_id` defaults to `0`, the "System" actor, until real user accounts
  arrive. After that, callers should set it explicitly via
  `Mast.Audit.scope_to_actor_fields/1` (to be added with auth).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @system_actor_id 0

  @derive {Inspect, except: [:metadata]}

  schema "audit_events" do
    field :event_type, :string
    field :actor_id, :integer, default: @system_actor_id
    field :subject_type, :string
    field :subject_id, :integer
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @castable ~w(event_type actor_id subject_type subject_id metadata)a
  @required ~w(event_type)a

  @doc "Returns the id used for system-originated audit events."
  def system_actor_id, do: @system_actor_id

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, @castable)
    |> validate_required(@required)
    |> validate_length(:event_type, max: 255)
  end
end
