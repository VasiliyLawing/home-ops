# Operations

## Placeholders

Before real deployment, replace:

```nix
homeOps.nas.host = "192.168.1.250";
homeOps.nas.export = "/volume1/media-stack";
```

And, if enabling qBittorrent:

```nix
homeOps.media.downloads.qbittorrent.vpn.peerPublicKey
homeOps.media.downloads.qbittorrent.vpn.endpoint
homeOps.media.downloads.qbittorrent.vpn.address
homeOps.media.downloads.qbittorrent.vpn.dns
```

The private key should remain outside the Nix store at:

```text
/run/secrets/qbittorrent-wg-private-key
```

## Runtime-generated tokens

`modules/secrets.nix` creates stable token files on first boot under:

```text
/var/lib/home-ops/secrets
```

These files are host-local and should never be committed.

## VPN safety checks

After enabling qBittorrent:

```bash
systemctl status qbittorrent-vpn-netns
systemctl status qbittorrent
ip netns exec qbittorrent ip route
ip netns exec qbittorrent nft list ruleset
```

Expected:

- default route points at `qbittorrent-wg`;
- nftables policy is default drop;
- LAN access is not present inside the namespace;
- qBittorrent stops if `qbittorrent-vpn-netns.service` stops.
