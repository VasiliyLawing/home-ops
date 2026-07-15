# Initial setup

This is the first-pass install checklist for bringing up `media-node`.


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

- SSH public key;
- NAS IP/export;
- public or private domain names if enabling ingress.

The install disk is already set for the current media-node NVMe. Change it only
if replacing the machine or disk.

Leave qBittorrent disabled until its Gluetun env file is on the host.

## 3. Install NixOS

Boot the target machine from a NixOS installer ISO, clone this repo, then use
Disko and `nixos-install` once the disk path is confirmed.

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

When qBittorrent is enabled, Nix automatically seeds its WebUI credentials and
baseline download settings before the container starts. qBit Manage then owns
category/tag hygiene on a timer, and the smoke test verifies qBittorrent has not
drifted back to the first-run `/config/Downloads` default.

This is intentional: Home Ops does not mutate qBittorrent live Web API settings
during deploy, because that path is sensitive to qBittorrent's cookie and
same-origin checks. Deploy should not fail because qBittorrent rejects a
post-start preference write.

The trade-off is explicit: deploys become more reliable, but live drift is
detected rather than silently corrected during `nixos-rebuild switch`. Run the
smoke test after deploys and after qBittorrent changes; if it fails, fix the
declared Nix/qBit Manage source and rerun the owning service.

The generated source credentials live at:

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
systemctl start qbit-manage-sync.service
systemctl start home-ops-smoke-test.service
journalctl -u home-ops-smoke-test.service -n 200 --no-pager
docker exec gluetun ip route
docker exec gluetun iptables -S
```

The Gluetun env file contains private material, so do not commit it to Git.

qBit Manage is enabled after qBittorrent is enabled, because both now use the
same Nix-generated WebUI credentials. It owns category/tag hygiene and leaves
destructive cleanup disabled.

If you change qBittorrent paths or ports later, change the Nix options, redeploy,
restart qBittorrent, and rerun the smoke test. If you change categories, update
the qBit Manage config and rerun `qbit-manage-sync.service`.

The Home Ops Arr download-client bootstrap creates/updates Sonarr and Radarr
qBittorrent download-client entries using the same generated qBittorrent WebUI
credentials.

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

NeutArr is available on localhost port `9705`. It runs with host networking,
so during its first-run wizard use plain loopback URLs for the Arr apps
(`host.docker.internal` does not resolve under host networking):

```text
http://127.0.0.1:8989
http://127.0.0.1:7878
http://127.0.0.1:8686
```

Aurral is available on localhost port `3001` (its native port; host networking
removed the old `8098` remap). During onboarding, point Lidarr to:

```text
http://127.0.0.1:8686
```

## 6. Run app sync jobs once

Home Ops owns Sonarr/Radarr qBittorrent download-client wiring:

```bash
sudo systemctl start home-ops-arr-download-clients.service
sudo journalctl -u home-ops-arr-download-clients.service
```

Home Ops owns Prowlarr app links to Sonarr/Radarr and the FlareSolverr indexer
proxy. Add actual Prowlarr indexers manually in the UI.
After Sonarr, Radarr, and Prowlarr have started at least once, run:

```bash
sudo systemctl start home-ops-prowlarr-bootstrap.service
sudo journalctl -u home-ops-prowlarr-bootstrap.service
```

Configarr owns Sonarr/Radarr quality profiles and TRaSH-Guides custom-format
sync. Then run:

```bash
sudo systemctl start configarr-sync.service
sudo journalctl -u configarr-sync.service
```

Bazarr's Sonarr/Radarr connections are Nix-owned:

```bash
sudo systemctl start home-ops-bazarr-bootstrap.service
sudo systemctl restart bazarr.service
sudo journalctl -u home-ops-bazarr-bootstrap.service
```

Seerr's Sonarr/Radarr settings are Nix-owned. Jellyfin wiring is added once a
real Jellyfin API key exists at `/var/lib/home-ops/secrets/jellyfin-api-key`.
Create the first Seerr admin through the UI once; Home Ops does not fake Seerr's
first-run initialized state. After that, rerun the bootstrap to wire Jellyfin's
Movies/TV libraries into Seerr:

```bash
sudo systemctl start home-ops-jellyfin-bootstrap.service
sudo journalctl -u home-ops-jellyfin-bootstrap.service
sudo systemctl start home-ops-seerr-bootstrap.service
sudo journalctl -u home-ops-seerr-bootstrap.service
```

Install the desired Jellyfin plugins:

```bash
sudo systemctl start home-ops-jellyfin-plugins.service
sudo journalctl -u home-ops-jellyfin-plugins.service -n 160 --no-pager
sudo systemctl restart jellyfin.service
```

After each deploy, run the on-demand smoke test:

```bash
sudo systemctl start home-ops-smoke-test.service
sudo journalctl -u home-ops-smoke-test.service -n 200 --no-pager
```

The Prowlarr bootstrap and Configarr also run daily through
`home-ops-prowlarr-bootstrap.timer` and `configarr-sync.timer`.
