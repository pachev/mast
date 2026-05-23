defmodule Mast.Fleet.Server do
  @moduledoc """
  A remote Linux host that Mast knows about.

  Most fields are populated by background checks (status, metrics,
  package_manager). The user only supplies name/host/user/port at creation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(unknown up down)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "servers" do
    field :name, :string
    field :host, :string
    field :user, :string, default: "ubuntu"
    field :port, :integer, default: 22

    field :os_id, :string
    field :package_manager, :string

    field :status, :string, default: "unknown"
    field :unreachable_count, :integer, default: 0
    field :last_seen_at, :utc_datetime_usec

    field :cpu, :float
    field :cpu_cores, :integer
    field :memory, :float
    field :disk, :float
    field :net_mb_s, :float
    field :load_1, :float
    field :load_5, :float
    field :load_15, :float
    field :memory_total_mb, :integer
    field :memory_used_mb, :integer
    field :disk_total_gb, :float
    field :disk_used_gb, :float
    field :agent_version, :string

    field :updates_available, :integer
    field :last_scan_at, :utc_datetime_usec
    field :last_scan, :map

    field :last_net_counters, :map
    field :last_disk_counters, :map

    belongs_to :private_key, Mast.Keys.PrivateKey
    belongs_to :project, Mast.Fleet.Project
    has_many :applications, Mast.Apps.Application
    has_many :releases, Mast.Fleet.Release

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def meta_changeset(server, attrs) do
    cast(server, attrs, [:os_id, :package_manager])
  end

  @doc false
  def scan_changeset(server, attrs) do
    server
    |> cast(attrs, [:updates_available, :last_scan])
    |> put_change(:last_scan_at, DateTime.utc_now())
  end

  @doc false
  def changeset(server, attrs) do
    server
    |> cast(attrs, [:name, :host, :user, :port, :private_key_id, :project_id])
    |> validate_required([:name, :host])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_length(:host, min: 1, max: 255)
    |> validate_number(:port, greater_than: 0, less_than_or_equal_to: 65_535)
    |> unique_constraint(:name)
    |> foreign_key_constraint(:private_key_id)
    |> foreign_key_constraint(:project_id)
  end

  @doc false
  def metrics_changeset(server, attrs) do
    server
    |> cast(attrs, [
      :cpu,
      :cpu_cores,
      :memory,
      :disk,
      :net_mb_s,
      :load_1,
      :load_5,
      :load_15,
      :memory_total_mb,
      :memory_used_mb,
      :disk_total_gb,
      :disk_used_gb,
      :agent_version,
      :os_id,
      :package_manager
    ])
    |> put_change(:status, "up")
    |> put_change(:unreachable_count, 0)
    |> put_change(:last_seen_at, DateTime.utc_now())
  end

  @doc false
  def counters_changeset(server, attrs) do
    cast(server, attrs, [:last_net_counters, :last_disk_counters])
  end

  @doc false
  def unreachable_changeset(server) do
    server
    |> change(%{
      status: "down",
      unreachable_count: (server.unreachable_count || 0) + 1
    })
  end

  def statuses, do: @statuses
end
