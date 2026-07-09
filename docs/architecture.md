# Architecture

This repo models one NixOS media/transcoding machine: `media-node`.

The NAS remains an appliance. It exports media storage over NFS. The NixOS host
runs the application layer.

## Module split

`modules/common/base.nix` contains reusable baseline host policy:

- SSH;
- Tailscale;
- users/groups;
- Nix settings;
- baseline firewall.

`modules/hosts/gmktec-media.nix` contains GMKtec/media-host details:

- AMD/kernel tuning;
- graphics/VAAPI packages;
- host firewall ports for ingress;
- render/video access.

Future hosts, such as a monitoring Pi, should import the common base plus their
own host profile. They should not import the GMKtec profile.

## Media split

The media stack is split by domain:

- `shared`: shared paths, Jellyfin, Jellyseerr, Podman backend;
- `downloads`: SABnzbd and VPN-isolated qBittorrent;
- `movies-tv`: Sonarr, Radarr, Prowlarr, Bazarr, Flaresolverr, Recyclarr, Neutarr;
- `books`: Audiobookshelf, Calibre-Web, Shelfmark;
- `music`: Lidarr, Navidrome, Aurral.

Apps packaged in Nixpkgs are run natively. Apps that are not packaged cleanly
are run through declarative OCI containers.

## qBittorrent VPN isolation

qBittorrent is disabled by default until WireGuard values are real.

When enabled, it is bound to a dedicated network namespace with:

- a WireGuard interface;
- default route through WireGuard;
- nftables default-drop rules inside the namespace;
- no normal LAN route;
- host-local Web UI proxy only.

If the VPN namespace is unavailable, qBittorrent is bound to that unit and stops.

SABnzbd is not VPN-isolated by default. It should use TLS to the Usenet provider.
