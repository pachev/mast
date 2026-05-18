defmodule Mast.Repo.Migrations.SwapDisterlForReleaseCommand do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      remove :node_name, :string
      remove :disterl_port, :integer
      remove :erlang_cookie, :binary

      # Path to a `bin/<release>` script on the remote host. Mast invokes
      # `<release_command> rpc "<expression>"` over SSH to introspect the
      # running BEAM. See ADR 0004 (revised).
      add :release_command, :string
    end
  end
end
