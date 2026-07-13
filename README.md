# Home Ops

NixOS monorepo for homelab machines.

Each machine owns its own project folder under `machines/`. Shared config only
lives in `shared/` when more than one machine actually needs it.

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
creates Jellyfin Movies/TV libraries, and completes Jellyfin wiring when a real
Jellyfin API key is placed on the host. Jellyfin plugin repositories and the
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

## Before deployment

Replace the public placeholders with real private values:

1. SSH public key in `machines/media-node/host.nix`;
2. NAS host/export in `machines/media-node/configuration.nix`;
3. real ingress hostnames before enabling `homeOps.ingress`;
4. Gluetun env file at `/var/lib/home-ops/secrets/gluetun-env` before enabling qBittorrent.

The Pi monitoring layer is intentionally not present yet.
