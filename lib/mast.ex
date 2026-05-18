defmodule Mast do
  @moduledoc """
  Mast — small self-hosted fleet monitor for Elixir / BEAM apps.

  Domain contexts live in this namespace:

    - `Mast.Fleet`   — servers (the boxes we watch)
    - `Mast.Keys`    — encrypted SSH private keys
    - `Mast.SSH`     — remote shell executor behaviour + impls
    - `Mast.Workers` — Oban-backed periodic + on-demand jobs
  """

  @doc """
  Current app version, sourced from `mix.exs` via `Application.spec/2`.
  Use this anywhere you'd otherwise hardcode a version string.
  """
  @spec version() :: String.t()
  def version do
    case Application.spec(:mast, :vsn) do
      nil -> "dev"
      vsn -> List.to_string(vsn)
    end
  end
end
