# Deploying Mast

This is how I run Mast in my home lab: a Proxmox LXC running Ubuntu, a
mix release, and a systemd unit. There is no Docker image and no
managed-cloud one-click. The same recipe works on any Linux box with
Erlang/Elixir installed and a reachable Postgres.

If you want something more turnkey, Mast is probably not the tool for
you. See the "Who this isn't for" section in the README.

This guide is a starting point that mirrors my own setup. It will get
more comprehensive over time; for now it is enough to get a working
deploy.

## 1. Provision a host

Anything that can run a Phoenix release is fine: a Proxmox LXC, a small
VM, an old Intel NUC, an EC2 instance. I use a Debian-family LXC because
that is what my lab runs on.

Rough sizing for a fleet of a dozen servers: 1 vCPU, 1 GB RAM, 4 GB
disk. Mast itself is tiny; Postgres dominates.

You will need:

- A Linux host with outbound network access
- Erlang/OTP 28 and Elixir 1.19 available at build time (mise is the
  simplest path; you can also use asdf or system packages)
- A reachable Postgres 14+ instance (local or remote)
- An unprivileged user to run the release as (I use `mast`, but pick
  whatever fits your shop)

## 2. Install system packages

On a fresh Debian/Ubuntu host I install:

```sh
sudo apt update
sudo apt install -y \
  build-essential git curl ca-certificates \
  postgresql \
  libssl-dev libncurses-dev autoconf m4 \
  unzip inotify-tools
```

`postgresql` is optional. If you already run Postgres elsewhere (a
container, a managed instance, a different box on the LAN), skip it and
point `DATABASE_URL` at that instead. A `docker run postgres:16` works
fine too. Mast does not care where the database lives as long as it can
reach it.

The rest of the packages are what Erlang needs to build from source via
mise. If you install Erlang/Elixir some other way (system packages, a
prebuilt tarball) you can trim accordingly.

## 3. Build the release

Mast uses [mise](https://mise.jdx.dev) for tool management and as its
task runner. Installing it first will make the rest of this guide (and
day-to-day work in the repo) much smoother:

```sh
curl https://mise.run | sh
```

On the target host (or any host with the same OTP major and architecture):

```sh
git clone https://github.com/pachev/mast.git
cd mast
mise install            # Erlang 28 + Elixir 1.19
mise run release        # builds _build/prod/rel/mast
```

This produces a self-contained release tree at
`_build/prod/rel/mast/`. You can leave it in place or move it somewhere
more conventional like `/opt/mast/` — the systemd unit just needs to
point at it.

## 4. Generate secrets

Two secrets you must generate once and keep safe.

```sh
mix phx.gen.secret                  # SECRET_KEY_BASE
openssl rand -base64 32             # MAST_VAULT_KEY (must decode to 32 bytes)
```

`MAST_VAULT_KEY` is the AES-256-GCM key that encrypts SSH private keys
at rest. If you lose it, every stored key becomes unreadable; rotate by
re-uploading keys after changing it. The app refuses to boot if the
value is missing or does not decode to 32 bytes.

## 5. Create the Postgres database

```sh
sudo -u postgres createuser --pwprompt mast
sudo -u postgres createdb --owner=mast mast_prod
```

Build the `DATABASE_URL` from those values:

```
ecto://mast:<password>@localhost/mast_prod
```

Postgres on a different host? Swap `localhost` for the hostname and
make sure the user can reach it.

## 6. Write the env file

Keep secrets out of the unit file. I put mine at `/etc/mast.env` owned
by `root:mast` with mode `0640`:

```sh
SECRET_KEY_BASE="<from mix phx.gen.secret>"
DATABASE_URL="ecto://mast:<password>@localhost/mast_prod"
PHX_HOST=192.168.0.71
PORT=4000
PHX_SERVER=true
MIX_ENV=prod
MAST_VAULT_KEY="<from openssl rand -base64 32>"
MAST_PUBLIC_URL="http://192.168.0.71:4000"
```

Notes on each:

- **PHX_HOST**: the hostname or IP the browser sees. LAN IP is fine for
  a home lab.
- **PORT**: the port Phoenix binds to. Pair with a reverse proxy if you
  want TLS or want to expose on 80/443.
- **MAST_PUBLIC_URL**: the URL Mast uses when generating absolute links
  (audit log targets, embedded references). Match `PHX_HOST` and
  `PORT`. If you front Mast with a reverse proxy on a different
  hostname or port, this should be the proxy's URL.
- **PHX_SERVER**: must be `true` for the release to actually start the
  web endpoint. Without it the BEAM runs but accepts no connections.

## 7. Run migrations

The release ships a thin `Mast.Release` module that runs Ecto
migrations without needing Mix at runtime:

```sh
sudo -u mast \
  env $(cat /etc/mast.env | xargs) \
  /opt/mast/bin/mast eval 'Mast.Release.migrate()'
```

Re-run this on every deploy that includes new migrations. It is
idempotent.

## 8. Systemd unit

Save as `/etc/systemd/system/mast.service`:

```ini
[Unit]
Description=Mast fleet dashboard
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=exec
User=mast
Group=mast
EnvironmentFile=/etc/mast.env
WorkingDirectory=/opt/mast
ExecStart=/opt/mast/bin/mast start
ExecStop=/opt/mast/bin/mast stop
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

Adjust `WorkingDirectory` and the `ExecStart` / `ExecStop` paths if you
kept the release at `_build/prod/rel/mast/` instead of moving it to
`/opt/mast/`.

Enable and start it:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now mast
sudo systemctl status mast
```

Logs:

```sh
sudo journalctl -u mast -f
```

## 9. Confirm it works

Open `http://<host>:4000` in a browser. If the dashboard loads with an
empty fleet, you are done. Add a server through the UI to verify the
SSH path end to end.

## Upgrading

```sh
cd /path/to/mast/checkout
git pull
mise run release
sudo systemctl stop mast
# if you copied the release to /opt/mast, copy again here
sudo -u mast env $(cat /etc/mast.env | xargs) \
  /opt/mast/bin/mast eval 'Mast.Release.migrate()'
sudo systemctl start mast
```

## What I deliberately did not include

- **A Docker image for Mast itself**: Mast is one process plus
  Postgres. Wrapping the app in a container does not pay for itself for
  a single-host home lab deploy, and it works against the "no extra
  agents, no extra layers" thesis the rest of the project follows.
  Postgres in a container is fine; the app is the part I keep on the
  metal.
- **TLS termination**: most home labs already front internal services
  with Caddy, nginx, or Traefik. Point yours at `localhost:4000` and
  set `MAST_PUBLIC_URL` to the public hostname.
- **Backup**: back up Postgres the way you back up the rest of your
  databases. The only state Mast keeps is in there.
