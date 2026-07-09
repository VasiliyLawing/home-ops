# Home Ops

Clan-managed NixOS configuration for a public-safe media/transcoding node.

The repo is intentionally optimized for NixOS rather than being a direct Docker
Compose migration.

## Shape

```text
Synology NAS
└── DSM storage appliance, NFS media export

media-node
├── NixOS + Clan
├── Jellyfin with host GPU access
├── movies / TV services
├── books / audiobooks services
├── music / podcast services
├── SABnzbd
├── qBittorrent isolated behind WireGuard
└── Tailscale + SSH deployment path
```

## Layout

```text
machines/media-node/            Machine-specific config
modules/base.nix                 Compatibility import for media-node base
modules/common/base.nix          Shared users, SSH, Tailscale, Nix settings
modules/hosts/gmktec-media.nix   GMKtec/media-host hardware profile
modules/disk.nix                 Disko install layout
modules/secrets.nix              Host-local generated runtime secrets
modules/nas-client.nix           Synology NFS mount
modules/ingress.nix              Caddy routes
modules/media/shared.nix         Shared media paths and Jellyfin/Jellyseerr
modules/media/downloads.nix      SABnzbd and VPN-isolated qBittorrent
modules/media/movies-tv.nix      Sonarr/Radarr/Prowlarr/Bazarr/Recyclarr/etc.
modules/media/books.nix          Audiobookshelf/Calibre-Web/Shelfmark
modules/media/music.nix          Lidarr/Navidrome/Aurral
```

## Before deployment

Replace the public placeholders with real private values:

1. install disk device in `modules/disk.nix`;
2. SSH public key in `modules/common/base.nix`;
3. NAS host/export in `machines/media-node/configuration.nix`;
4. domain names in `modules/ingress.nix`;
5. Proton/WireGuard values before enabling qBittorrent.

The Pi monitoring layer is intentionally not present yet.
