# ADR 0006: SSH key storage and encryption

Status: Accepted
Date: 2026-05-18

## Context

Today (v0.3) Mast reads SSH keys from `priv/ssh/` on the host running the app.
That works for a single operator with one key but breaks every other case:

- Multiple servers needing different keys.
- Keys arriving via the web UI (paste/upload) rather than the filesystem.
- Multi-user installs where the operator running Mast is not the same person
  managing the fleet.

We need to store private keys in the database, but private keys are about as
sensitive as data gets: a database dump or a logging mistake leaks production
access to the whole fleet.

## Decision

### Encryption at rest with Cloak

Use [`cloak`](https://hex.pm/packages/cloak) +
[`cloak_ecto`](https://hex.pm/packages/cloak_ecto) for field-level encryption.
Cloak is the standard Elixir choice for this — it wraps `:crypto`'s AES-256-GCM
in an Ecto type that encrypts on write and decrypts on read, so the encrypted
column is transparent at the schema level.

We considered hand-rolling AES-GCM on top of `:crypto.crypto_one_time_aead/7`.
Three dozen lines of code instead of a 200-line dep, but the well-trodden
path is worth more here than a few KB of dependency weight. Audit story is
better too: "we used the battle-tested library" vs. "we wrote our own."

### Master key supplied by environment

The encryption key is **never** in the database, **never** in the repo, **never**
in `config/dev.exs`:

- Production reads `MAST_VAULT_KEY` (a 32-byte base64 secret) from the
  environment via `config/runtime.exs`. The app refuses to boot if it's unset.
- Development reads the same env var, but `config/dev.exs` falls back to a
  fixed dev-only key (committed) so onboarding is one `mise run dev`. The
  dev key is **not** a secret — it just lets the dev DB be readable across
  machines. Production must override it.
- Test env uses a fixed test-only key (committed). All tests use the same
  key so encrypted fixtures round-trip.

The operator's responsibility is to source `MAST_VAULT_KEY` from whatever
secrets manager they already use (1Password CLI, AWS Secrets Manager, Doppler,
Vault, k8s secrets — Mast doesn't care).

### Schema layout

```
Mast.PrivateKey
  - id                 (bigint, PK)
  - name               (string, plain)         # "elpajo prod", "home lab", etc.
  - body               (binary, encrypted)     # the PEM
  - fingerprint        (string, plain)         # "SHA256:abc…" — display + dedup
  - algorithm          (string, plain)         # "rsa", "ed25519", "ecdsa"
  - comment            (string, plain, nullable) # last segment of the public key
  - inserted_at, updated_at
```

Only `body` is encrypted. Everything else is plain so the listing page and
the "key dropdown when adding a server" can render without ever decrypting.
The `fingerprint` doubles as a uniqueness key — adding the same key twice
under different names is rejected. The plain columns also let us safely log
"key #4 used to connect to server #7" without leaking material.

### Decrypt only at the call site

`Mast.SSH.SSHKit.run/2` is the **only** place that calls
`Mast.Keys.material(key)` to get the plaintext PEM. The result is fed to
`:ssh.connect/4` via a `key_cb` callback module and goes out of scope
immediately. The decrypted PEM never:

- gets written to disk
- appears in Ecto changeset errors (the field is dropped from `inspect/1`)
- appears in Phoenix HTML rendering (no template ever receives it)
- appears in Oban job args (workers receive `server_id`, not key material)

### No passphrase support in v0.4

Encrypted private keys (those with their own PEM-level passphrase) are a
**separate** problem from encryption at rest:

- We'd need to store the passphrase somewhere, defeating the point.
- Or prompt for it on every use, which doesn't compose with background workers.
- Or use ssh-agent forwarding, which is a different architecture.

For v0.4, Mast rejects encrypted PEMs at upload time with a clear error.
Users who need passphrase protection should generate a separate unencrypted
key for Mast and add it to the target servers' `authorized_keys`.
Passphrase support is deferred to a future ADR.

### Validation rules at upload

- Must parse with `:public_key.pem_decode/1` and yield exactly one
  `RSAPrivateKey` / `ECPrivateKey` / `OpenSSHPrivateKey` entry.
- Must **not** be encrypted (`:public_key.pem_decode/1` returns `{:Encrypted, _, _}`
  when it is).
- Must derive a valid public key — we compute the SHA-256 fingerprint and
  store it; if that fails, the key is malformed.
- Maximum 16KB (the largest sensible RSA 8192 PEM is ~6KB). Hard cap to
  reject obvious junk.

## Consequences

- **DB dump is no longer a fleet-takeover event.** Ciphertext + fingerprints
  leak the *existence* of keys but not their contents. The threat model
  becomes "compromise the runtime AND the secrets manager" rather than
  "compromise the DB."
- **Operator must manage `MAST_VAULT_KEY`.** Losing it makes every stored
  key permanently unreadable. We'll document key rotation later — Cloak
  supports labelled multi-key configs out of the box.
- **One key per server in v0.4.** A server has at most one
  `private_key_id`. Future revision could allow per-server fallback chains
  (try key A, then B); not needed yet.
- **`priv/ssh/` is deprecated** after the migration lands. The directory
  still works for the no-keys-yet-installed case, but the dev seed will
  push us toward DB-stored keys.
- **Encrypted keys (PEM-level) rejected.** Workaround: generate an
  unencrypted key for Mast and authorize it on the target boxes. Most
  ops teams already do this (the "deploy key" pattern).

## What we explicitly did NOT decide here

- **Key rotation cadence and tooling** — deferred until we have a second
  key to rotate to.
- **Audit log schema** — we'll add an `audit_events` table when there's a
  user account model to attribute actions to.
- **Hardware-backed keys (TPM, YubiKey)** — out of scope; if you need this
  you're already running something more serious than Mast.
- **Multi-user / RBAC** — single-user assumption stands until a real
  second user shows up.
