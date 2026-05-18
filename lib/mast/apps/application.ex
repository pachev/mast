defmodule Mast.Apps.Application do
  @moduledoc """
  An Erlang/OTP application observed running on a registered server.

  Populated by `Mast.Workers.AppProbe` via distributed-Erlang RPC. See
  ADR 0004 for the monitoring strategy.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(running stopped unreachable unknown)

  schema "applications" do
    field :name, :string
    field :node_name, :string
    field :version, :string
    field :status, :string, default: "unknown"
    field :memory_mb, :float
    field :processes, :integer
    field :msg_queue, :integer
    field :otp_release, :string
    field :uptime_seconds, :integer
    field :last_seen_at, :utc_datetime_usec
    field :last_probe, :map

    belongs_to :server, Mast.Fleet.Server

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(app, attrs) do
    app
    |> cast(attrs, [
      :server_id,
      :name,
      :node_name,
      :version,
      :status,
      :memory_mb,
      :processes,
      :msg_queue,
      :otp_release,
      :uptime_seconds,
      :last_seen_at,
      :last_probe
    ])
    |> validate_required([:server_id, :name, :node_name, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:server_id, :name])
  end

  def statuses, do: @statuses
end
