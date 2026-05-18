defmodule Mast.Encrypted.Binary do
  @moduledoc """
  Cloak.Ecto type for encrypting raw binary fields (e.g. SSH key bodies).
  """
  use Cloak.Ecto.Binary, vault: Mast.Vault
end
