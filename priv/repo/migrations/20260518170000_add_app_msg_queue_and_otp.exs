defmodule Mast.Repo.Migrations.AddAppMsgQueueAndOtp do
  use Ecto.Migration

  def change do
    alter table(:applications) do
      add :msg_queue, :integer
      add :otp_release, :string
    end
  end
end
