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
`bin/<release> rpc` script. A Release today assumes a host-installed mix
release; containerized deployments are out of scope until a future ADR
adds them.
_Avoid_: app, application, service

**Release Name**:
The explicit handle an Operator gives a Release. Optional. When set, it
is the Release's Effective Handle. When unset, the Effective Handle
derives from `release_command` instead.
_Avoid_: release id, app name, slug

**Effective Handle**:
The identifier a Release is known by within its Server: its Release Name
if set, otherwise the basename of `release_command`. Unique within a
Server. No two Releases on one Server may share an Effective Handle.
_Avoid_: name (when you mean the derived value), slug

**Log Source**:
The kind of log stream a Release exposes. One of `:systemd` (a unit
read via `journalctl`), `:file` (a single absolute path read via
`tail -F`), or `:none`. Config-only — not its own entity, not its own
table. If a Release ever needed multiple streams, this would graduate
to a noun; today it does not.
_Avoid_: log driver, log backend, log channel

**Log Target**:
The address inside a Log Source — a systemd unit name for `:systemd`,
an absolute file path for `:file`. Validated per Log Source by the
adapter that knows the shape.
_Avoid_: log path (misleading for systemd), log locator

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

**Project**:
A named grouping of Servers that belong together (typically the boxes
that run one product across its environments — e.g. a `blog` Project
containing the staging and prod Servers for that product). A Server
belongs to at most one Project; Servers without a Project render as
plain rows in the Fleet view, not under an "Unassigned" pseudo-group.
Projects do not own Releases directly; they group at the Server layer.
_Avoid_: group, cluster, stack, env, environment (Project is the
grouping; environment is a sub-axis if we ever add it)

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

**Log Source Adapter**:
A module implementing the `Mast.Logs.Source` behaviour. Knows two
things and only two things: how to build the streaming command for its
Log Source kind, and how to validate a Log Target. The SSH machinery
that actually runs the command lives in the Executor. One adapter per
Log Source value (`Mast.Logs.Systemd`, `Mast.Logs.File`).
_Avoid_: log driver, log handler

## Relationships

- A **Server** hosts zero or more **Releases**
- A **Release** has exactly one **Log Source** (defaults to `:none`)
- A **Scan** of a **Server** produces zero or more **Patches**
- An **Apply** on a **Server** consumes one or more **Patches**
- A **Server** has at most one **Private Key** (v0.4)
- Every **Private Key** body is encrypted with the **Vault Key**
- Every meaningful action by an **Actor** produces an **Audit Event**
- A **Server** is **Checked** periodically
- A **Release** is **Probed** periodically
- A **Server** belongs to at most one **Project**

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

> **Dev:** "If a **Release**'s **Log Source** is `:none`, what shows in the
> Logs tab?"
> **PJ:** "An empty state pointing at the Release's Settings tab. We never
> open an SSH stream for a Release that hasn't told us where to look."

> **Dev:** "Two **Releases** on the same **Server** with the same derived
> name — what wins?"
> **PJ:** "Neither. The Operator has to set an explicit **Release Name** on
> at least one. Two Releases on a Server sharing an effective handle is an
> invariant the system never allows — not merely a validation it attempts."

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
- "environment" (dev/staging/prod) is **not** a Mast concept yet. A
  Project may contain Servers from multiple environments; the
  distinction lives in the Server's name today. If cross-Project
  environment filtering ever matters, that becomes its own axis (likely
  a small enum on Server) in a future ADR.
- "app" vs "release" — resolved: **Release** is canonical at the
  configuration layer (one row per Release in the `releases` table). At
  runtime, every Release contains many **Applications** (OTP apps loaded
  in the BEAM). ServerLive's primary tab is "Releases" and links to
  `MastWeb.ReleaseLive`. `MastWeb.AppLive` remains as the per-Application
  drill-in page (`/apps/:id`). `release_command` stays as a field name
  because it points at `bin/<release>` and renaming it is churn for no
  clarity gain.

</content>
</invoke>