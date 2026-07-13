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

`home-ops-qbittorrent-config.service` seeds the qBittorrent WebUI
username/password into:

```text
/var/lib/qbittorrent/qBittorrent/qBittorrent.conf
```

It uses qBittorrent's PBKDF2-SHA512 WebUI password format and runs before the
`docker-qbittorrent.service` container starts. It also seeds the baseline
behavior that should not be click-configured after every reinstall:

```text
Default save path:        /data/torrents/complete
Incomplete path:          /data/torrents/incomplete
Incomplete path enabled:  true
UPnP/NAT-PMP:             disabled
Random listen port:       disabled
WebUI port:               8081
Listening port:           6881
```

qBit Manage owns the category/tag hygiene layer using the same `/data/torrents`
view qBittorrent uses. Its configured categories are `movies`, `tv`, `music`,
`books`, and `audiobooks`, each under `/data/torrents/complete/<category>`.

There is intentionally no post-start qBittorrent API mutator in the deployment
path. qBittorrent's Web API rejects state-changing calls when auth/host headers
do not line up exactly, so the repo avoids making deploy success depend on that
fragile path. Use `home-ops-smoke-test.service` to verify live qBittorrent state
instead of mutating it during deploy.

This trades automatic post-start correction for safer deployments. A NixOS
switch should converge the machine and restart services, not fail because
qBittorrent rejects a WebUI-origin-sensitive preference write. Drift is still
covered: the smoke test checks qBittorrent's live API state and fails loudly if
paths or safety settings no longer match the declared model.

When changing qBittorrent defaults after deployment:

- edit `homeOps.media.downloads.qbittorrent.*` options for startup-safe defaults
  such as save path, incomplete path, WebUI port, listening port, UPnP, or
  random-port behavior;
- redeploy and restart `docker-qbittorrent.service` so
  `home-ops-qbittorrent-config.service` can seed the config before qBittorrent
  starts;
- edit `machines/media-node/services/media/config/qbit-manage/config.yml` for
  category/tag layout, then run `qbit-manage-sync.service`;
- run `home-ops-smoke-test.service` to confirm the live Web API state matches
  the declared model.

Do not reintroduce a deploy-blocking Web API preference mutator unless
qBittorrent's auth/origin behavior is explicitly handled and tested.

The host also exposes `/data` as a Nix-owned compatibility path to the NAS data
root. This keeps native Sonarr/Radarr and containerized qBittorrent using the
same paths, so Arr health checks do not see qBittorrent-only paths such as
`/config/Downloads`.

`home-ops-arr-download-clients.service` then creates or updates the Sonarr and
Radarr `qBittorrent` download clients from the live Arr API schemas. It uses:

```text
Sonarr category: tv
Radarr category: movies
qBittorrent API: 127.0.0.1:8081
```

This service intentionally does not require a post-start qBittorrent API config
unit. It only needs qBittorrent running and reachable with the generated WebUI
credentials.

The `HOME_OPS_QBIT_USERNAME_FILE` and `HOME_OPS_QBIT_PASSWORD_FILE` environment
variables in this unit are still required. They are used to create/update the
Sonarr and Radarr download-client records, not to mutate qBittorrent's global
WebUI preferences.

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
iampuid0/neutarr:1.8.0
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

`home-ops-prowlarr-bootstrap.service` handles Prowlarr app links to
Sonarr/Radarr and shared indexer proxies such as FlareSolverr.

This intentionally replaces Buildarr. Buildarr's Prowlarr plugin failed while
reading current Prowlarr remote state before it could apply our desired app-link
config. The Home Ops bootstrap talks directly to Prowlarr's live schemas
instead.

Prowlarr only uses FlareSolverr when the proxy and indexer have matching tags.
The bootstrap therefore creates a `flaresolverr` tag and attaches it to both
the FlareSolverr proxy. Add actual indexers manually in Prowlarr and attach the
same `flaresolverr` tag to Cloudflare-prone indexers.

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

## Seerr bootstrap

`home-ops-seerr-bootstrap.service` owns Seerr's Sonarr/Radarr settings and can
also wire Jellyfin.

Sonarr/Radarr use the Nix-generated API keys. Jellyfin requires a real API key
created after Jellyfin has an admin user. Place that key on the host at:

```text
/var/lib/home-ops/secrets/jellyfin-api-key
```

Then run:

```bash
systemctl start home-ops-seerr-bootstrap.service
journalctl -u home-ops-seerr-bootstrap.service -n 120 --no-pager
```

When the Jellyfin key exists, the bootstrap also pulls Jellyfin's Movies/TV
media folders, enables them in Seerr, and sets the LAN Jellyfin external URL to
`http://media-node:8096` after Seerr's first admin user exists.

Before Seerr's first admin user exists, the bootstrap intentionally skips
Jellyfin-in-Seerr settings and resets Seerr's media server type back to
`NOT_CONFIGURED`. This keeps Seerr in the first-run setup flow, because the
Jellyfin auth endpoint requires the first admin login to include the selected
server type. Home Ops does not fake Seerr's first-run `initialized` state.

If the Jellyfin key is missing, the bootstrap still writes Sonarr/Radarr
settings and logs that Jellyfin was skipped. After writing settings, the service
restarts Seerr so it reloads `settings.json`.

## Media-node smoke test

`home-ops-smoke-test.service` is intentionally on-demand. It does not run during
deploy, because a transient warm-up delay should not block a NixOS switch. Treat
it as a post-deploy safety gate: deploy first, let services settle, then run the
smoke test to catch live-state drift.

Run it after a deploy or after changing app wiring:

```bash
systemctl start home-ops-smoke-test.service
journalctl -u home-ops-smoke-test.service -n 200 --no-pager
```

It checks failed systemd units, NAS media paths, qBittorrent's Gluetun network
namespace, qBittorrent's API, Sonarr/Radarr download-client wiring, Prowlarr app
links and FlareSolverr proxy, Jellyfin Movies/TV libraries, and Seerr's
Jellyfin/Sonarr/Radarr settings.

## Jellyfin bootstrap

`home-ops-jellyfin-bootstrap.service` creates the baseline Jellyfin libraries:

```text
Movies -> /mnt/nas/data/media/movies
TV     -> /mnt/nas/data/media/tv
```

It uses the host-local Jellyfin API key at:

```text
/var/lib/home-ops/secrets/jellyfin-api-key
```

Run it after Jellyfin's first admin user and API key exist:

```bash
systemctl start home-ops-jellyfin-bootstrap.service
journalctl -u home-ops-jellyfin-bootstrap.service -n 80 --no-pager
```

## Jellyfin plugins

`home-ops-jellyfin-plugins.service` owns the desired Jellyfin plugin repository
list and installs the selected plugin packages on demand.

Repositories:

```text
Intro Skipper     -> https://intro-skipper.org/manifest.json
IAmParadox27      -> https://www.iamparadox.dev/jellyfin/plugins/manifest.json
Jellyfin Enhanced -> https://raw.githubusercontent.com/n00bcodr/jellyfin-plugins/main/10.11/manifest.json
```

Desired plugins:

```text
File Transformation
Intro Skipper
Media Bar
Jellyfin Enhanced
```

Run it after the Jellyfin admin/API-key setup is complete:

```bash
systemctl start home-ops-jellyfin-plugins.service
journalctl -u home-ops-jellyfin-plugins.service -n 160 --no-pager
systemctl restart jellyfin.service
```

After the restart, hard-refresh Jellyfin Web. Intro Skipper may also need its
scheduled task run from the Jellyfin dashboard before skip markers appear.

## Bazarr bootstrap

`home-ops-bazarr-bootstrap.service` owns Bazarr's Sonarr/Radarr connection
settings. It edits only the relevant scalar keys in Bazarr's config file and
preserves the rest of the config.

It writes:

```text
Sonarr URL/API key -> 127.0.0.1:8989
Radarr URL/API key -> 127.0.0.1:7878
Default undefined audio/subtitle language -> en
```

It runs before Bazarr starts:

```bash
systemctl status home-ops-bazarr-bootstrap.service
journalctl -u home-ops-bazarr-bootstrap.service -n 80 --no-pager
systemctl status bazarr.service
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
