# Dev-only seed data. Idempotent — re-running is safe.
#
#   mix run priv/repo/seeds.exs

alias Mast.Fleet

if Fleet.list_servers() == [] do
  {:ok, _} =
    Fleet.create_server(%{
      name: "hermes",
      host: "3.151.234.78",
      user: "ubuntu",
      port: 22
    })

  IO.puts("Seeded: hermes")
else
  IO.puts("Servers already present, skipping seed.")
end
