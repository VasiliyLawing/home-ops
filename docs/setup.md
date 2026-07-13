# Initial setup

This is the first-pass install checklist for bringing up `media-node`.

For the Windows dev shell, see `docs/workstation-wsl.md`.

## 1. Prepare the NAS

On the NAS:

1. Create `/volume1/media-stack` or your preferred export.
2. Enable NFS.
3. Allow the future `media-node` LAN IP to mount the export.

## 2. Replace placeholders

Edit:

```text
machines/media-node/disk.nix
machines/media-node/host.nix
machines/media-node/configuration.nix
machines/media-node/services/ingress.nix
```

Replace:

- install disk device;
- SSH public key;
- NAS IP/export;
- public or private domain names.

Leave qBittorrent disabled until its Gluetun env file is on the host.

## 3. Install NixOS

Boot the target machine from a NixOS installer ISO, clone this repo, then use
Clan/Disko to install once the disk path is confirmed.

## 4. Join Tailscale

On `media-node`:

```bash
sudo tailscale up
```

Confirm the host is reachable as:

```text
root@media-node
```

## 5. Enable qBittorrent

Create a host-local Gluetun env file:

```text
/var/lib/home-ops/secrets/gluetun-env
```

Use this committed non-secret template as a starting point:

```text
machines/media-node/services/media/config/gluetun.env.example
```

For Proton WireGuard, the important values are:

```text
VPN_SERVICE_PROVIDER=protonvpn
VPN_TYPE=wireguard
WIREGUARD_PRIVATE_KEY=...
SERVER_COUNTRIES=Netherlands
PORT_FORWARD_ONLY=on
VPN_PORT_FORWARDING=on
```

Then enable:

```nix
homeOps.media.downloads.qbittorrent.enable = true;
```

When qBittorrent is enabled, Nix automatically seeds its WebUI credentials
before the container starts. The generated source credentials live at:

```text
/var/lib/home-ops/secrets/qbittorrent-env
```

It contains:

```text
QBIT_USER=...
QBIT_PASS=...
```

Verify:

```bash
systemctl status docker-gluetun
systemctl status home-ops-qbittorrent-config
systemctl status docker-qbittorrent
docker exec gluetun ip route
docker exec gluetun iptables -S
```

The Gluetun env file contains private material, so do not commit it to Git.

qBit Manage can be enabled after qBittorrent is enabled, because both now use
the same Nix-generated WebUI credentials.

Then enable:

```nix
homeOps.media.qbitManage.enable = true;
```

Shelfmark is already wired to use the same generated Prowlarr/qBittorrent
credentials. Once qBittorrent is enabled, Shelfmark can submit book torrents
with the `books` category and audiobook torrents with the `audiobooks` category.

The default book library service is Calibre-Web-Automated on localhost port
`8083`. It uses:

```text
/mnt/nas/data/media/books/imports
/mnt/nas/data/media/books/library
/var/lib/home-ops/calibre-web-automated
```

For a fresh install, open Calibre-Web-Automated and change the default admin
password after the first successful deploy.

NeutArr is available on localhost port `9705`. During its first-run wizard, use
the host gateway URLs for Arr apps:

```text
http://host.docker.internal:8989
http://host.docker.internal:7878
http://host.docker.internal:8686
```

Aurral is available on localhost port `8098`. During onboarding, point Lidarr to:

```text
http://host.docker.internal:8686
```

## 6. Run Buildarr and Configarr once

Buildarr owns public Prowlarr indexers, Prowlarr app links to Sonarr/Radarr,
and Sonarr/Radarr qBittorrent download-client wiring.
After Sonarr, Radarr, and Prowlarr have started at least once, run:

```bash
sudo systemctl start buildarr-sync.service
sudo journalctl -u buildarr-sync.service
```

Configarr owns Sonarr/Radarr quality profiles and TRaSH-Guides custom-format
sync. Then run:

```bash
sudo systemctl start configarr-sync.service
sudo journalctl -u configarr-sync.service
```

They also run daily through `buildarr-sync.timer` and `configarr-sync.timer`.
