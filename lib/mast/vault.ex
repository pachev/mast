defmodule Mast.Vault do
  @moduledoc """
  Cloak vault for at-rest encryption of sensitive fields (e.g. SSH private
  key bodies).

  Configured at runtime — see `config/runtime.exs`, which loads the master
  key from `MAST_VAULT_KEY` (a 32-byte base64 secret). Dev and test envs
  use fixed fallback keys so onboarding is one `mise run dev`; production
  refuses to boot if the env var is unset.

  See ADR 0006 for the decisions behind this module.
  """
  use Cloak.Vault, otp_app: :mast
end
