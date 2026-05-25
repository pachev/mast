defmodule Mast.Patches.Run do
  @moduledoc """
  The last apply-updates run for a server (one row per server). Persisted so a
  reloaded LiveView can reattach to an in-flight run and replay its log.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(running done error)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "patch_runs" do
    field :run_id, :string
    field :scope, :string
    field :package, :string
    field :status, :string, default: "running"
    field :exit_code, :integer
    field :log, :string, default: ""
    field :error, :string

    belongs_to :server, Mast.Fleet.Server

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [:server_id, :run_id, :scope, :package, :status, :exit_code, :log, :error])
    |> validate_required([:server_id, :run_id, :scope, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:server_id)
  end
end
