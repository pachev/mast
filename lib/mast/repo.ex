defmodule Mast.Repo do
  use Ecto.Repo,
    otp_app: :mast,
    adapter: Ecto.Adapters.Postgres
end
