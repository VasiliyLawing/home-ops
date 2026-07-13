# Home Ops

NixOS monorepo for homelab machines.

Each machine owns its own project folder under `machines/`. Shared config only
lives in `shared/` when more than one machine actually needs it.

## Setup

Full walkthrough in `docs/setup.md`; day-2 tasks in `docs/operations.md`.
Everything is declarative except a handful of one-time manual steps:

1. Replace the public placeholders: SSH public key in
   `machines/media-node/host.nix`, NAS host/export in
   `machines/media-node/configuration.nix`, real ingress hostnames before
   enabling `homeOps.ingress`.
2. Install with Disko + `nixos-install` from the NixOS ISO, then
   `sudo tailscale up` on the machine.
3. Put the Gluetun VPN env file at `/var/lib/home-ops/secrets/gluetun-env`
   before enabling qBittorrent.
4. Complete the Jellyfin first-run wizard, create an API key, place it at
   `/var/lib/home-ops/secrets/jellyfin-api-key`, then start the on-demand
   Jellyfin/Seerr bootstrap units.
5. Add Prowlarr indexers in the UI (deliberately not code).

## Credentials

Service credentials are generated on the machine at first boot and live as
root-only files under `/var/lib/home-ops/secrets/`. They are never in Git or
the Nix store. To get the qBittorrent WebUI login (username is `admin`):

```bash
sudo cat /var/lib/home-ops/secrets/qbittorrent-webui-password
```

The Arr API keys sit in the same directory as `<app>-api-key` files.

## Shape

```text
Synology NAS
`-- DSM storage appliance, NFS media export

machines/media-node
|-- NixOS
|-- Jellyfin with host GPU access
|-- movies / TV services
|-- books / audiobooks services, including Shelfmark search/download wiring
|-- music / podcast services
|-- SABnzbd
|-- qBittorrent isolated through Gluetun
`-- Tailscale + SSH deployment path
```

## Layout

```text
machines/
|-- media-node/
|   |-- configuration.nix
|   |-- host.nix
|   |-- disk.nix
|   |-- secrets.nix
|   |-- nas-client.nix
|   |-- scripts/
|   |   `-- runtime-secrets/
|   `-- services/
|       |-- ingress.nix
|       `-- media/
|           |-- config/
|           |-- shared.nix
|           |-- jellyfin-bootstrap.nix
|           |-- jellyfin-plugins.nix
|           |-- downloads.nix
|           |-- arr-download-clients.nix
|           |-- bazarr-bootstrap.nix
|           |-- prowlarr-bootstrap.nix
|           |-- configarr.nix
|           |-- qbit-manage.nix
|           |-- unpackerr.nix
|           |-- seerr-bootstrap.nix
|           |-- smoke-test.nix
|           |-- movies-tv.nix
|           |-- books.nix
|           `-- music.nix
`-- shared/
    `-- default.nix
```

Nix files declare the system. The only machine-owned scripts are runtime
secret/bootstrap helpers where code is genuinely clearer than Nix strings.
Static app config files live under `services/.../config/` only when an app has
an actual config artifact worth owning in Git. Home Ops owns Prowlarr app links,
Prowlarr indexer proxies, and Sonarr/Radarr qBittorrent download-client
bootstrap directly through the Arr APIs. Actual Prowlarr indexers are added
manually in the UI. Home Ops also bootstraps Seerr's Sonarr/Radarr settings,
creates Jellyfin Movies/TV libraries, seeds Jellyfin's VAAPI hardware
transcoding (780M decode/encode, HDR tone mapping), and completes Jellyfin
wiring when a real Jellyfin API key is placed on the host. Jellyfin plugin repositories and the
desired plugin set are installed through an on-demand bootstrap service. Bazarr's
Sonarr/Radarr connections are bootstrapped from the same generated Arr API keys. Configarr owns Sonarr/Radarr quality
profiles and TRaSH-Guides sync declaratively. Unpackerr handles archive
extraction after downloads. Shelfmark is wired to Prowlarr and qBittorrent
through generated host-local secrets. qBittorrent's baseline paths and ports are
seeded before startup, qBit Manage owns category/tag hygiene after startup, and
the smoke test verifies the live Web API state instead of mutating it during
deploy.
`home-ops-smoke-test.service` is the on-demand post-deploy check for the whole
media stack.

The Pi monitoring layer is intentionally not present yet.
