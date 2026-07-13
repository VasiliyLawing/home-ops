# Operations

## Placeholders

Before real deployment, replace:

```nix
homeOps.nas.host = "10.10.10.2";
homeOps.nas.export = "/volume1/media-stack";
```

These live in:

```text
machines/media-node/configuration.nix
```

If enabling qBittorrent, create a Gluetun env file for your VPN provider and
place it on the host at:

```text
/var/lib/home-ops/secrets/gluetun-env
```

This path is declared here:

```nix
homeOps.media.downloads.gluetun.environmentFile
```

The Gluetun env file contains VPN private material and must remain outside Git
and outside the Nix store.

Use `machines/media-node/services/media/config/gluetun.env.example` as the
non-secret template. Gluetun remains provider-neutral; change the env file for
different VPN providers instead of changing the qBittorrent module.

## NAS NFS mount

The Synology export is mounted over the direct NAS link:

```text
media-node enp3s0: 10.10.10.1
Synology NAS:       10.10.10.2
Export:             /volume1/media-stack
Mount:              /mnt/nas/data
```

Synology DSM exposed the share reliably with NFSv3 over TCP during initial
setup. The NixOS mount therefore uses:

```text
nfsvers=3,proto=tcp,mountproto=tcp,nolock
```

If the automount looks present but the directory appears empty or returns
`No such device`, test the raw mount with:

```bash
mount -vvv -t nfs -o nfsvers=3,proto=tcp,mountproto=tcp,nolock 10.10.10.2:/volume1/media-stack /mnt/nas/data
```

## Runtime-generated secrets

`machines/media-node/secrets.nix` creates stable host-local secrets on first
boot under:

```text
/var/lib/home-ops/secrets
```

These files are host-local and should never be committed.

Generated files include:

```text
sonarr-api-key
radarr-api-key
prowlarr-api-key
lidarr-api-key
qbittorrent-webui-username
qbittorrent-webui-password
arr-api-keys.env
unpackerr-env
qbittorrent-env
shelfmark-env
```

`home-ops-arr-configs.service` seeds those API keys into the Arr app
`config.xml` files before Sonarr/Radarr/Prowlarr/Lidarr start.

When qBittorrent is enabled, `home-ops-qbittorrent-config.service` seeds the
qBittorrent WebUI username/password into:

```text
/var/lib/qbittorrent/qBittorrent/qBittorrent.conf
```

It uses qBittorrent's PBKDF2-SHA512 WebUI password format and runs before the
`docker-qbittorrent.service` container starts.

The same bootstrap also owns the baseline qBittorrent behavior that should not
be click-configured after every reinstall:

```text
Default save path:        /data/torrents/complete
Incomplete path:          /data/torrents/incomplete
Incomplete path enabled:  true
UPnP/NAT-PMP:             disabled
Random listen port:       disabled
WebUI port:               8081
Listening port:           6881
```

`home-ops-arr-download-clients.service` then creates or updates the Sonarr and
Radarr `qBittorrent` download clients from the live Arr API schemas. It uses:

```text
Sonarr category: tv
Radarr category: movies
qBittorrent API: 127.0.0.1:8081
```

`shelfmark-env` supplies Shelfmark with the generated Prowlarr API key and the
same qBittorrent WebUI username/password. Non-secret Shelfmark settings live in
`machines/media-node/services/media/books.nix`.

The default books stack uses Calibre-Web-Automated rather than native
Calibre-Web. This is intentional: native Calibre-Web requires an existing
Calibre `metadata.db`, while Calibre-Web-Automated can initialize a fresh
library and has explicit `NETWORK_SHARE_MODE=true` handling for NFS/SMB-backed
storage.

Default book paths:

```text
/mnt/nas/data/media/books/imports   -> CWA ingest folder
/mnt/nas/data/media/books/library   -> Calibre library
/var/lib/home-ops/calibre-web-automated -> CWA config/app data
```

Native Calibre-Web is still available as an advanced opt-in once a valid
Calibre library already exists:

```nix
homeOps.media.books.calibreWebAutomated.enable = false;
homeOps.media.books.calibreWeb.enable = true;
```

NeutArr uses the upstream Docker Hub image:

```text
iampuid0/neutarr:latest
```

It is exposed on localhost port `9705`, stores config in
`/var/lib/home-ops/neutarr`, and should be configured in its first-run wizard to
reach host-native Arr services through:

```text
http://host.docker.internal:8989  # Sonarr
http://host.docker.internal:7878  # Radarr
http://host.docker.internal:8686  # Lidarr
```

Aurral uses the upstream GHCR image pinned to the stable 1.x line:

```text
ghcr.io/lklynet/aurral:1.76.0
```

It is exposed on localhost port `8098`, persists app data in
`/var/lib/home-ops/aurral`, and writes generated music flows under:

```text
/mnt/nas/data/media/music/aurral
```

## Configarr sync

Configarr handles Sonarr/Radarr quality-profile and TRaSH-Guides custom-format
sync. The Radarr `HD Bluray + WEB` profile is intentionally loaded from the
Recyclarr template include without a local `quality_profiles` override; adding a
partial override can make Radarr reject profile creation even when the systemd
job itself exits successfully.

It runs as a scheduled one-shot job:

```bash
systemctl status configarr-sync.timer
systemctl start configarr-sync.service
journalctl -u configarr-sync.service -n 240 --no-pager
```

The job runs Docker directly from systemd. It loads Sonarr/Radarr API keys from:

```text
/var/lib/home-ops/secrets/arr-api-keys.env
```

The committed config file lives at:

```text
machines/media-node/services/media/config/configarr/config.yml
```

Configarr keeps its writable template cache under:

```text
/var/lib/home-ops/configarr/repos
```

When verifying a manual run, search the log for `ERROR` and confirm the
execution summary shows Radarr success, not just that systemd marked the job as
finished.

## Prowlarr bootstrap

`home-ops-prowlarr-bootstrap.service` handles public Prowlarr indexers and the
Prowlarr links to Sonarr/Radarr.

This intentionally replaces Buildarr. Buildarr's Prowlarr plugin failed while
reading current Prowlarr remote state before it could apply our desired indexer
and app-link config. The Home Ops bootstrap talks directly to Prowlarr's live
schemas instead.

It runs as a scheduled one-shot job:

```bash
systemctl status home-ops-prowlarr-bootstrap.timer
systemctl start home-ops-prowlarr-bootstrap.service
journalctl -u home-ops-prowlarr-bootstrap.service -n 160 --no-pager
```

The committed non-secret config file lives at:

```text
machines/media-node/services/media/config/prowlarr/bootstrap.json
```

API keys are read directly from the host-local generated secret files under
`/var/lib/home-ops/secrets`.

## Unpackerr

Unpackerr extracts archives from completed Sonarr/Radarr downloads so the Arr
apps can import them cleanly.

It runs as a container using:

```text
/mnt/nas/data -> /data
```

That path must stay identical to the `/data` view used by qBittorrent, Sonarr,
and Radarr.

It reads API keys from:

```text
/var/lib/home-ops/secrets/unpackerr-env
```

Check it with:

```bash
systemctl status docker-unpackerr
journalctl -u docker-unpackerr -n 160 --no-pager
```

## qBit Manage

qBit Manage is enabled once qBittorrent is enabled and the Gluetun env file is
present. It owns the safe qBittorrent hygiene layer: categories, tracker-error
tags, and the shared `/data/torrents` category paths.

Destructive cleanup remains disabled in the committed config:

```text
rem_unregistered: false
rem_orphaned: false
skip_cleanup: true
skip_qb_version_check: true
```

`skip_qb_version_check` is enabled because qBit Manage can lag qBittorrent by a
patch release. The qBittorrent Web API is still reached and authenticated during
each run.

It reads qBittorrent credentials from:

```text
/var/lib/home-ops/secrets/qbittorrent-env
```

It contains:

```text
QBIT_USER=...
QBIT_PASS=...
```

`home-ops-qbittorrent-config.service` configures qBittorrent to use those same
credentials before the qBittorrent container starts.

It runs as a scheduled one-shot job:

```bash
systemctl status qbit-manage-sync.timer
systemctl start qbit-manage-sync.service
journalctl -u qbit-manage-sync.service -n 160 --no-pager
```

The committed non-secret config lives at:

```text
machines/media-node/services/media/config/qbit-manage/config.yml
```

qBit Manage categories include `books` and `audiobooks` so Shelfmark-submitted
torrents land in the same `/data/torrents/complete/...` layout seen by
qBittorrent.

qBit Manage also gets a writable runtime config directory for generated logs:

```text
/var/lib/home-ops/qbit-manage/config/logs
```

## Shelfmark

Shelfmark is wired as the books/audiobooks search and download UI. It uses:

- Prowlarr for source/indexer search;
- qBittorrent for torrent downloads;
- `books` and `audiobooks` qBittorrent categories;
- `/books` and `/audiobooks` ingest folders inside the container.

It runs with Docker host networking so it can reach the host-local Prowlarr and
qBittorrent APIs at `127.0.0.1`. Its own UI is bound to localhost:

```text
http://127.0.0.1:8099
```

If you later enable Shelfmark direct web/IRC sources, treat Shelfmark itself as
an external downloader and decide whether to put it behind its own VPN path.

## VPN safety checks

After enabling qBittorrent:

```bash
systemctl status docker-gluetun
systemctl status home-ops-qbittorrent-config
systemctl status docker-qbittorrent
docker exec gluetun ip route
docker exec gluetun iptables -S
```

Expected:

- qBittorrent uses `--network=container:gluetun`;
- the Web UI is only bound on `127.0.0.1`;
- Gluetun owns the VPN firewall/kill switch;
- qBittorrent has no independent host networking path.
