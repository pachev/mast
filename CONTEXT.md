# Mast

Self-hosted dashboard for a small fleet of Linux servers running Elixir
releases. Tracks liveness, OS patches, and (planned) BEAM-level health of
the releases on each box.

## Language

**Fleet**:
The set of all Servers registered with Mast. Scoped to machines only —
Releases are not part of the Fleet.
_Avoid_: cluster, inventory, estate

**Server**:
A registered Linux machine in the Fleet that Mast reaches over SSH.
_Avoid_: host, box, node, machine

**Release**:
A mix-built Elixir application running on a Server, addressable via its
`bin/<release> rpc` script.
_Avoid_: app, application, service

**Patch**:
An available apt package upgrade on a Server — one row per upgradable
package after a Scan.
_Avoid_: update, upgrade

**Scan**:
A run that lists the Patches currently available on a Server
(`apt list --upgradable`). Read-only.
_Avoid_: check, poll (for this specific action)

**Apply**:
A run that installs one or more Patches on a Server. Mutating.
_Avoid_: update (verb), upgrade (verb), install

**Private Key**:
The SSH private key Mast uses to authenticate to a Server. Stored as an
encrypted PEM in `private_keys`. Within Mast there is only one kind of
private key, so the "SSH" qualifier is dropped.
_Avoid_: SSH key, key (unqualified), deploy key

**Vault Key**:
The 32-byte master secret (`MAST_VAULT_KEY`) Cloak uses to encrypt
Private Keys at rest. Lives in the environment, never in the database.
_Avoid_: master key, encryption key, cloak key

**Operator**:
The human running Mast and managing the fleet. No account row exists
yet (single-user assumption, ADR 0006/0007).
_Avoid_: user, admin, owner

**Actor**:
Whatever caused an Audit Event — an Operator (future) or the System
pseudo-actor (`actor_id = 0`) when a background worker is the cause.
_Avoid_: author, source

**Audit Event**:
An immutable `audit_events` row recording a meaningful state change
(key created, server added, scan run, apply run). Append-only.
_Avoid_: event (unqualified), log entry, audit log row

**Check**:
A host-level observation of a Server over SSH (reachability, CPU, RAM,
disk). Periodic, read-only.
_Avoid_: probe (for the host), poll, ping

**Probe**:
A release-level observation of a Release via `bin/<release> rpc`
(liveness, scheduler, memory, app state). Periodic, read-only.
_Avoid_: check (for the release), healthcheck, scrape

**Executor**:
The behaviour that runs a command against a Server. SSH is the only
impl today; future impls (e.g. disterl to an in-cluster agent) plug in
behind the same callback.
_Avoid_: SSH (when referring to the abstraction), runner, transport

## Relationships

- A **Server** hosts zero or more **Releases**
- A **Scan** of a **Server** produces zero or more **Patches**
- An **Apply** on a **Server** consumes one or more **Patches**
- A **Server** has at most one **Private Key** (v0.4)
- Every **Private Key** body is encrypted with the **Vault Key**
- Every meaningful action by an **Actor** produces an **Audit Event**
- A **Server** is **Checked** periodically
- A **Release** is **Probed** periodically

## Example dialogue

> **Dev:** "When the **Scan** finishes, do we re-**Check** the **Server**?"
> **PJ:** "No. A **Scan** lists **Patches**; a **Check** captures CPU/RAM/disk.
> Same SSH connection, different commands, different cadence."

> **Dev:** "If a **Release**'s **Probe** fails, does the **Server** show as down?"
> **PJ:** "No. The **Server** is up iff its **Check** succeeds. A failed
> **Probe** only marks that **Release** unhealthy."

> **Dev:** "Can two **Servers** share a **Private Key**?"
> **PJ:** "Yes — many Servers, one Private Key. But a Server has at most one
> Private Key in v0.4."

## Flagged ambiguities

- "key" was used for both **Private Key** (the SSH PEM) and **Vault Key**
  (the Cloak master secret) — resolved: always qualify.
- "update" / "upgrade" / "patch" were used interchangeably — resolved:
  **Patch** is the noun, **Apply** is the verb. apt's words are not ours.
- "check" / "probe" were used interchangeably across ADRs — resolved:
  **Check** = Server (SSH), **Probe** = Release (rpc). Different subjects.
- "user" vs "operator" vs "admin" — resolved: **Operator** until a real
  account model exists; **Actor** is the audit-log field that holds
  Operator (future) or System (today).

</content>
</invoke>