defmodule Mast.Fleet.Release do
  @moduledoc """
  An Elixir Release running on a Server. Identified within its Server
  by an effective handle: `name` if set, otherwise the basename of
  `release_command`.

  See ADR 0008.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @log_sources ~w(systemd file none)
  @name_regex ~r/^[a-z0-9][a-z0-9_-]*$/

  schema "releases" do
    belongs_to :server, Mast.Fleet.Server

    field :name, :string
    field :release_command, :string
    field :log_source, :string, default: "none"
    field :log_target, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Returns the operator-visible identifier for this Release within its
  Server. Prefers an explicit `name`; falls back to the basename of
  `release_command`. Returns `nil` if neither is set.
  """
  def effective_handle(%__MODULE__{name: name}) when is_binary(name) and name != "", do: name

  def effective_handle(%__MODULE__{name: _, release_command: rc})
      when is_binary(rc) and rc != "",
      do: Path.basename(rc)

  def effective_handle(_), do: nil

  @doc false
  def changeset(release, attrs) do
    release
    |> cast(attrs, [:server_id, :name, :release_command, :log_source, :log_target])
    |> validate_required([:server_id])
    |> validate_length(:name, max: 64)
    |> validate_length(:release_command, max: 512)
    |> validate_length(:log_target, max: 512)
    |> validate_inclusion(:log_source, @log_sources)
    |> normalize_blank(:name)
    |> normalize_blank(:release_command)
    |> normalize_blank(:log_target)
    |> validate_name()
    |> validate_release_command()
    |> validate_log_target()
    |> assoc_constraint(:server)
    |> unique_constraint([:server_id, :name],
      name: :releases_server_id_name_index,
      message: "is already taken on this Server"
    )
    |> validate_handle_uniqueness()
  end

  defp normalize_blank(changeset, field) do
    case get_change(changeset, field) do
      "" -> put_change(changeset, field, nil)
      _ -> changeset
    end
  end

  defp validate_name(changeset) do
    case get_field(changeset, :name) do
      nil ->
        changeset

      name when is_binary(name) ->
        if Regex.match?(@name_regex, name) do
          changeset
        else
          add_error(
            changeset,
            :name,
            "must start with [a-z0-9] and contain only [a-z0-9_-]"
          )
        end
    end
  end

  defp validate_release_command(changeset) do
    case get_field(changeset, :release_command) do
      nil ->
        changeset

      path when is_binary(path) ->
        if String.starts_with?(path, "/") and not String.contains?(path, "\n") do
          changeset
        else
          add_error(changeset, :release_command, "must be an absolute path")
        end
    end
  end

  defp validate_log_target(changeset) do
    source = get_field(changeset, :log_source) || "none"
    target = get_field(changeset, :log_target)

    case {source, target} do
      {"none", _} ->
        changeset

      {_, nil} ->
        add_error(changeset, :log_target, "can't be blank")

      {source, target} ->
        case Mast.Logs.validate_target(source, target) do
          :ok -> changeset
          {:error, msg} -> add_error(changeset, :log_target, msg)
        end
    end
  end

  defp validate_handle_uniqueness(changeset) do
    server_id = get_field(changeset, :server_id)
    name = get_field(changeset, :name)
    rc = get_field(changeset, :release_command)
    handle = effective_handle(%__MODULE__{name: name, release_command: rc})

    cond do
      is_nil(server_id) ->
        changeset

      is_nil(handle) ->
        changeset

      taken?(server_id, handle, get_field(changeset, :id)) ->
        add_error(
          changeset,
          :release_command,
          "another Release on this Server already uses the handle #{inspect(handle)}; set an explicit name"
        )

      true ->
        changeset
    end
  end

  defp taken?(server_id, handle, current_id) do
    import Ecto.Query

    base =
      from r in __MODULE__,
        where: r.server_id == ^server_id

    base =
      if current_id, do: where(base, [r], r.id != ^current_id), else: base

    base
    |> Mast.Repo.all()
    |> Enum.any?(fn r -> effective_handle(r) == handle end)
  end
end
