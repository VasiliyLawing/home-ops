# Architecture

This is a machine-owned monorepo.

The rule is simple:

- if config belongs to one machine, it lives under that machine;
- if config is truly shared by multiple machines, it lives under `shared/`.

## Machines

```text
machines/media-node
`-- homelab media/transcoding machine

shared
`-- small machine-agnostic baseline
```

The NAS remains an appliance. It exports media storage over NFS. `media-node`
runs the application layer.

## Shared layer

`shared/default.nix` intentionally stays small:

- timezone;
- `homeops` user baseline;
- core CLI packages;
- Nix flakes/trusted-users/GC policy.

It does not enable SSH, Tailscale, media groups, or NAS mounts. Those are
machine-owned concerns.

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
- `services/media/jellyfin-bootstrap.nix`: Jellyfin Movies/TV library and VAAPI transcoding bootstrap;
- `services/media/downloads.nix`: SABnzbd and VPN-isolated qBittorrent;
- `services/media/movies-tv.nix`: Sonarr, Radarr, Prowlarr, Bazarr, Flaresolverr, Neutarr;
- `services/media/bazarr-bootstrap.nix`: Bazarr Sonarr/Radarr settings bootstrap;
- `services/media/arr-download-clients.nix`: Sonarr/Radarr qBittorrent download-client bootstrap;
- `services/media/prowlarr-bootstrap.nix`: Prowlarr app-link and indexer-proxy bootstrap;
- `services/media/configarr.nix`: Configarr profile/custom-format/TRaSH sync for Sonarr and Radarr;
- `services/media/qbit-manage.nix`: qBit Manage category/tag/cleanup skeleton;
- `services/media/unpackerr.nix`: archive extraction for completed downloads;
- `services/media/seerr-bootstrap.nix`: Seerr Jellyfin/Sonarr/Radarr settings bootstrap;
- `services/media/books.nix`: Audiobookshelf, Calibre-Web, Shelfmark;
- `services/media/music.nix`: Lidarr, Navidrome, Aurral, plus the Soulseek
  pipeline (slskd, Soularr) and a nightly in-place beets tagging run.

The Nix modules describe services, options, dependencies, and systemd wiring.
Shell scripts are kept to the bootstrap boundary only: generating host-local
secrets, seeding Arr `config.xml` files before the apps start, and seeding
qBittorrent WebUI credentials before the VPN-isolated container starts.

Static app config files live under `services/.../config/` only when there is a
real config artifact worth owning in Git. The Prowlarr bootstrap has JSON
because app links and indexer proxies are real desired state. Actual Prowlarr
indexers are added manually in the UI because public indexer availability and
anti-bot behavior can be brittle. Configarr has one because quality profiles,
quality definitions, and TRaSH-Guides custom-format
choices are real desired state. qBit Manage has one because qBittorrent
categories and hygiene rules are real desired state. Most services in this stack
are configured by NixOS module options, runtime state, or their own web/API
setup, so they should not get placeholder YAML files just for symmetry.

## Declarative app configuration layers

NixOS owns the services, storage, firewall, VPN island, and schedules. App-level
configuration is split so tools do not fight each other:

- Configarr owns Sonarr/Radarr quality profiles, quality definitions, and
  TRaSH-Guides custom-format sync.
- `home-ops-jellyfin-bootstrap.service` owns Jellyfin Movies/TV libraries and
  seeds VAAPI hardware-transcoding settings for the Radeon 780M (all-codec
  hardware decode, HEVC/AV1 encode, HDR tone mapping, transcode throttling).
- `home-ops-bazarr-bootstrap.service` owns Bazarr's Sonarr/Radarr connections.
- `home-ops-prowlarr-bootstrap.service` owns Prowlarr app links to
  Sonarr/Radarr and shared indexer proxies such as FlareSolverr.
- `home-ops-seerr-bootstrap.service` owns Seerr's Sonarr/Radarr settings and
  wires Jellyfin once a real Jellyfin API key exists on the host.
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
`shelfmark-env` file. Shelfmark runs with host networking (UI on `0.0.0.0`,
reachable over Tailscale; the NixOS firewall keeps the LAN out) so it can
reach the host-local Prowlarr, qBittorrent, and Calibre-Web-Automated APIs.

NeutArr and Aurral are helper applications with first-run onboarding flows.
They are kept in containers because neither has a native NixOS module today,
but they use verified upstream images and run with host networking — host
services are reachable at plain `127.0.0.1` from inside them, and their UIs
are reachable over Tailscale only (LAN blocked by the firewall).

Configarr runs as a scheduled one-shot container from `configarr-sync.timer`.
Systemd runs Docker directly and loads Sonarr/Radarr API keys from the
Nix-generated `arr-api-keys.env` file.

Prowlarr bootstrap runs as `home-ops-prowlarr-bootstrap.service` plus a daily
timer. It uses the live Prowlarr provider schemas, then fills only the small set
of values this repo owns: app links and indexer proxies. This replaces Buildarr
for Prowlarr because the Buildarr Prowlarr plugin proved brittle against current
Prowlarr remote state.

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

There is intentionally no post-start `home-ops-qbittorrent-api-config.service`.
qBittorrent's live Web API is cookie-authenticated and strict about
same-origin/host checks, which made post-start preference mutation too brittle
for the deployment path. Baseline qBittorrent settings are seeded before
startup, qBit Manage handles category/tag hygiene after startup, and the smoke
test verifies the live state did not drift.

The trade-off is reliability over silent correction: Home Ops avoids failing a
deployment on qBittorrent's WebUI auth/origin behavior, while still detecting
drift with the smoke test. If drift appears, the fix is to update the declared
owner and restart or rerun it, not to patch qBittorrent imperatively during
deploy.

Future changes follow that boundary: change startup-safe defaults such as WebUI
credentials, default save path, incomplete path, WebUI port, listening port,
UPnP, or random-port behavior in `services/media/downloads.nix`, then restart
qBittorrent so the pre-start bootstrap can rewrite
`/var/lib/qbittorrent/qBittorrent/qBittorrent.conf`. Change category/tag layout
in `services/media/config/qbit-manage/config.yml`, then run
`qbit-manage-sync.service`. If the smoke test reports drift after deployment,
fix the declarative source and restart/rerun the owning service rather than
adding a new deploy-time Web API mutator.

The replacement model splits qBittorrent ownership by responsibility:

| Responsibility | Owner | When it runs |
| --- | --- | --- |
| WebUI credentials, default save path, incomplete path, WebUI port, listening port, UPnP, random-port behavior | `home-ops-qbittorrent-config.service` | before `docker-qbittorrent.service` starts |
| qBittorrent categories, tags, tracker-error tags, hygiene rules | `qbit-manage-sync.service` | after qBittorrent is running, plus timer |
| Sonarr/Radarr qBittorrent download-client entries | `home-ops-arr-download-clients.service` | after Sonarr/Radarr/qBittorrent are running |
| Runtime verification of live qBittorrent state | `home-ops-smoke-test.service` | on demand after deploy |

The host exposes `/data` as a compatibility path to the NAS data root, so native
Sonarr/Radarr and containerized qBittorrent use the same path language.

qBit Manage uses the same `/data/torrents` view, so category and hygiene logic
sees paths exactly as qBittorrent sees them. It owns category/tag sync after
qBittorrent is running. Destructive cleanup is intentionally disabled until
explicitly reviewed.

The Arr API keys are Nix-owned runtime secrets. `home-ops-runtime-secrets`
generates them on first boot, and `home-ops-arr-configs` writes them into
Sonarr/Radarr/Prowlarr/Lidarr config files before those services start.

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

The path invariant below is what lets native services and containers cooperate
without remote path mappings. qBittorrent sees the NAS as `/data` from inside
its container; Sonarr/Radarr see the same path through the host-side `/data`
symlink managed by Nix tmpfiles. The real storage remains on the Synology mount.

```text
qBittorrent container: /data/torrents/...
Sonarr/Radarr host:    /data/torrents/... via /data -> /mnt/nas/data
NAS real path:         /mnt/nas/data/torrents/...
```

`home-ops-qbittorrent-config.service` seeds qBittorrent's baseline save path,
incomplete path, WebUI port, listening port, and UPnP/random-port settings before
the container starts. `qbit-manage-sync.service` owns the category/tag layer
after qBittorrent is running. `home-ops-smoke-test.service` verifies the live
qBittorrent API state, including that the default save path has not fallen back
to `/config/Downloads`.

No other Home Ops service consumes the removed
`home-ops-qbittorrent-api-config.service`. `home-ops-arr-download-clients` only
needs qBittorrent to be running with stable credentials; it does not require a
post-start qBittorrent preference mutation step.

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

## Trust model

The firewall trusts `tailscale0` outright, and the *arr apps are seeded with
`AuthenticationMethod=External` and no reverse proxy in front of them. That is
a deliberate trade: every device on the tailnet gets unauthenticated admin
access to Sonarr/Radarr/Prowlarr/Lidarr/Bazarr (which includes remote code
execution via custom-script settings). This is acceptable only while the
tailnet contains exclusively this household's trusted devices. If the tailnet
ever grows (shared nodes, exit nodes for guests), switch the seeded
`AuthenticationMethod` to `Forms` or put an authenticating proxy in front.
