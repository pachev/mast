# ADR 0003: SSH executor as a behaviour

Status: Accepted
Date: 2026-05-18

## Context

Every server interaction is a remote shell command: `cat /etc/os-release`,
`apt list --upgradable`, `df -h`, `apt install -y curl`. Two needs:

1. Production: actually run SSH against real hosts.
2. Tests: never touch the network, never depend on a daemon.

## Decision

Define `Mast.SSH` as a thin behaviour:

```elixir
@callback run(server :: %Mast.Fleet.Server{}, command :: String.t()) ::
            {:ok, String.t()} | {:error, term()}
```

Two implementations:

- `Mast.SSH.SSHKit` — wraps the `sshkit` hex package (which itself wraps
  Erlang's `:ssh` application). Reuses connections per-host inside the
  process. Equivalent of Coolify's ControlMaster multiplexing, but in-VM.
- `Mast.SSH.Stub` — an in-memory canned-response map for tests. Stores last
  command per server for assertions.

Selection is via `Application.get_env(:mast, :ssh)`. `config/test.exs` pins
to the stub.

## Why a behaviour (not Mox)

We control both impls, the API surface is tiny (one callback), and avoiding a
test-only dep keeps `mix.exs` honest. If the surface grows past ~3 callbacks
we'll switch to Mox.

## Security notes (lifted from Coolify)

- Package names must match `^[a-zA-Z0-9._+:-]+$` *before* shell escaping.
- All parser-bound commands run with `LANG=C` to keep output English.
- Refuse commands containing the heredoc delimiter to prevent breakout.

## Consequences

- 100% of `Mast.Fleet` patch logic is unit-testable.
- We pay for an extra indirection on every call; negligible vs. SSH RTT.
