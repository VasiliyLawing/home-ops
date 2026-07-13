# Home Ops

Clan-managed NixOS monorepo for homelab and workstation machines.

Each machine owns its own project folder under `machines/`. Shared config only
lives in `shared/` when more than one machine actually needs it.

## Shape

```text
Synology NAS
`-- DSM storage appliance, NFS media export

machines/media-node
|-- NixOS + Clan
|-- Jellyfin with host GPU access
|-- movies / TV services
|-- books / audiobooks services, including Shelfmark search/download wiring
|-- music / podcast services
|-- SABnzbd
|-- qBittorrent isolated through Gluetun
`-- Tailscale + SSH deployment path

machines/workstation-wsl
|-- NixOS-WSL + Clan
|-- Neovim/dev tooling
`-- no Tailscale or server services
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
|           |-- downloads.nix
|           |-- arr-download-clients.nix
|           |-- prowlarr-bootstrap.nix
|           |-- configarr.nix
|           |-- qbit-manage.nix
|           |-- unpackerr.nix
|           |-- movies-tv.nix
|           |-- books.nix
|           `-- music.nix
|-- workstation-wsl/
|   |-- configuration.nix
|   |-- host.nix
|   `-- services/
|       `-- neovim.nix
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
and completes Jellyfin wiring when a real Jellyfin API key is placed on the
host. Configarr owns Sonarr/Radarr quality
profiles and TRaSH-Guides sync declaratively. Unpackerr handles archive
extraction after downloads. Shelfmark is wired to Prowlarr and qBittorrent
through generated host-local secrets. qBit Manage owns qBittorrent categories
and safe hygiene rules once qBittorrent is enabled on the machine.

## Before deployment

Replace the public placeholders with real private values:

1. SSH public key in `machines/media-node/host.nix`;
2. NAS host/export in `machines/media-node/configuration.nix`;
3. real ingress hostnames before enabling `homeOps.ingress`;
4. Gluetun env file at `/var/lib/home-ops/secrets/gluetun-env` before enabling qBittorrent.

The Pi monitoring layer is intentionally not present yet.
