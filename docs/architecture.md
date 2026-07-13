# Architecture

This is a machine-owned monorepo.

The rule is simple:

- if config belongs to one machine, it lives under that machine;
- if config is truly shared by multiple machines, it lives under `shared/`.

## Machines

```text
machines/media-node
`-- homelab media/transcoding machine

machines/workstation-wsl
`-- local Windows WSL development shell

shared
`-- small baseline used by both machines
```

The NAS remains an appliance. It exports media storage over NFS. `media-node`
runs the application layer.

## Shared layer

`shared/default.nix` intentionally stays small:

- timezone;
- `homeops` user baseline;
- core CLI packages;
- Nix flakes/trusted-users/GC policy.

It does not enable SSH, Tailscale, media groups, NAS mounts, or workstation
tooling. Those are machine-owned concerns.

## media-node

`machines/media-node/` owns the whole homelab/media stack:

- `host.nix`: GMKtec/AMD hardware, SSH, Tailscale, firewall, media groups;
- `disk.nix`: Disko install layout;
- `nas-client.nix`: NAS NFS mount;
- `secrets.nix`: host-local runtime secret generation and Arr config seeding;
- `scripts/runtime-secrets/`: small bootstrap helpers for secrets, Arr
  `config.xml` files, and qBittorrent WebUI credentials;
- `services/ingress.nix`: Caddy routes;
- `services/media/*.nix`: the media application stack.

The media stack is still split by domain:

- `services/media/shared.nix`: shared paths, Jellyfin, Seerr, Docker backend;
- `services/media/downloads.nix`: SABnzbd and VPN-isolated qBittorrent;
- `services/media/movies-tv.nix`: Sonarr, Radarr, Prowlarr, Bazarr, Flaresolverr, Neutarr;
- `services/media/arr-download-clients.nix`: Sonarr/Radarr qBittorrent download-client bootstrap;
- `services/media/prowlarr-bootstrap.nix`: Prowlarr public indexer and app-link bootstrap;
- `services/media/configarr.nix`: Configarr profile/custom-format/TRaSH sync for Sonarr and Radarr;
- `services/media/qbit-manage.nix`: qBit Manage category/tag/cleanup skeleton;
- `services/media/unpackerr.nix`: archive extraction for completed downloads;
- `services/media/books.nix`: Audiobookshelf, Calibre-Web, Shelfmark;
- `services/media/music.nix`: Lidarr, Navidrome, Aurral.

The Nix modules describe services, options, dependencies, and systemd wiring.
Shell scripts are kept to the bootstrap boundary only: generating host-local
secrets, seeding Arr `config.xml` files before the apps start, and seeding
qBittorrent WebUI credentials before the VPN-isolated container starts.

Static app config files live under `services/.../config/` only when there is a
real config artifact worth owning in Git. The Prowlarr bootstrap has JSON
because public indexers and app links are real desired state. Configarr has one
because quality profiles, quality definitions, and TRaSH-Guides custom-format
choices are real desired state. qBit Manage has one because qBittorrent
categories and hygiene rules are real desired state. Most services in this stack
are configured by NixOS module options, runtime state, or their own web/API
setup, so they should not get placeholder YAML files just for symmetry.

## Declarative app configuration layers

NixOS owns the services, storage, firewall, VPN island, and schedules. App-level
configuration is split so tools do not fight each other:

- Configarr owns Sonarr/Radarr quality profiles, quality definitions, and
  TRaSH-Guides custom-format sync.
- `home-ops-prowlarr-bootstrap.service` owns Prowlarr public indexers and
  Prowlarr app links to Sonarr/Radarr.
- `home-ops-arr-download-clients.service` owns Sonarr/Radarr qBittorrent
  download-client definitions using each app's own API schema.
- qBit Manage owns qBittorrent categories, tags, and cleanup once enabled.
- Unpackerr owns post-download archive extraction for Sonarr/Radarr imports.

Sonarr, Radarr, and Shelfmark use qBittorrent categories that match qBit
Manage:

```text
Sonarr -> tv
Radarr -> movies
Shelfmark books -> books
Shelfmark audiobooks -> audiobooks
```

Other media apps are intentionally not wired to qBittorrent unless they submit
downloads. Jellyfin, Audiobookshelf, Calibre-Web-Automated, Navidrome, and
Seerr are library or request/consumer apps in this design; they do not need
qBittorrent download-client credentials.

Shelfmark is the exception in the books module. It is a search/request/download
app, so it gets Prowlarr and qBittorrent credentials from the Nix-generated
`shelfmark-env` file. Shelfmark runs with host networking and binds its UI to
`127.0.0.1` so it can reach the host-local Prowlarr, qBittorrent, and
Calibre-Web-Automated APIs without exposing qBittorrent beyond localhost.

NeutArr and Aurral are helper applications with first-run onboarding flows.
They are kept in containers because neither has a native NixOS module today,
but they use verified upstream images and local-only port bindings. For host
service access, they receive Docker's `host.docker.internal` gateway alias.

Configarr runs as a scheduled one-shot container from `configarr-sync.timer`.
Systemd runs Docker directly and loads Sonarr/Radarr API keys from the
Nix-generated `arr-api-keys.env` file.

Prowlarr bootstrap runs as `home-ops-prowlarr-bootstrap.service` plus a daily
timer. It uses the live Prowlarr provider schemas, then fills only the small set
of values this repo owns. This replaces Buildarr for Prowlarr because the
Buildarr Prowlarr plugin proved brittle against current Prowlarr remote state.

Unpackerr runs as a lightweight container with the same `/data` mount path used
by qBittorrent, Sonarr, and Radarr, so it sees archives at the same paths the
Arr apps report.

qBit Manage is enabled with qBittorrent. It expects
`/var/lib/home-ops/secrets/qbittorrent-env` with:

```text
QBIT_USER=...
QBIT_PASS=...
```

`home-ops-qbittorrent-config.service` bootstraps qBittorrent to use those same
credentials before the qBittorrent container starts. That bootstrap is
intentionally separate because modern qBittorrent images generate a temporary
first-run password unless explicitly seeded.

It uses the same `/data/torrents` view that qBittorrent uses, so category and
hygiene logic sees paths exactly as qBittorrent sees them. Destructive cleanup
is intentionally disabled until explicitly reviewed.

The Arr API keys are Nix-owned runtime secrets. `home-ops-runtime-secrets`
generates them on first boot, and `home-ops-arr-configs` writes them into
Sonarr/Radarr/Prowlarr/Lidarr config files before those services start.

## workstation-wsl

`machines/workstation-wsl/` owns the local dev shell:

- `host.nix`: NixOS-WSL settings, zsh, CLI tooling;
- `services/neovim.nix`: Neovim and language-server tooling.

It intentionally does not enable Tailscale or an SSH server.

## qBittorrent VPN isolation

qBittorrent is disabled by default until its Gluetun VPN env file is real.

The download island is provider-neutral:

```text
Gluetun container
`-- VPN client, firewall, kill switch, local Web UI port bind

qBittorrent container
`-- shares Gluetun's network namespace
```

Gluetun receives provider-specific settings from:

```text
/var/lib/home-ops/secrets/gluetun-env
```

For Proton, that env file can contain the familiar Gluetun variables:

```text
VPN_SERVICE_PROVIDER=protonvpn
VPN_TYPE=wireguard
WIREGUARD_PRIVATE_KEY=...
SERVER_COUNTRIES=Netherlands
PORT_FORWARD_ONLY=on
VPN_PORT_FORWARDING=on
```

qBittorrent does not get its own network namespace. It runs with
`--network=container:gluetun`, so if Gluetun is down, qBittorrent has no separate
internet path. Its config stays on the local SSD, and the NAS data mount is
mapped into the container as `/data`.

The host-side NAS layout is:

```text
/mnt/nas/data/
|-- torrents/
|   |-- incomplete/
|   `-- complete/
|       |-- movies/
|       |-- tv/
|       |-- music/
|       |-- books/
|       `-- audiobooks/
`-- media/
    |-- movies/
    |-- tv/
    |-- music/
    |-- books/
    |   `-- imports/
    `-- audiobooks/
        `-- imports/
```

SABnzbd is not VPN-isolated by default. It should use TLS to the Usenet provider.
