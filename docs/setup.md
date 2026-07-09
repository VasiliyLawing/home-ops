# Initial setup

This is the first-pass install checklist for bringing up `media-node`.

## 1. Prepare the NAS

On the NAS:

1. Create `/volume1/media-stack` or your preferred export.
2. Enable NFS.
3. Allow the future `media-node` LAN IP to mount the export.

## 2. Replace placeholders

Edit:

```nix
modules/disk.nix
modules/common/base.nix
machines/media-node/configuration.nix
modules/ingress.nix
```

Replace:

- install disk device;
- SSH public key;
- NAS IP/export;
- public or private domain names.

Leave qBittorrent disabled until WireGuard values are ready.

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

Get WireGuard values from your VPN provider:

- private key;
- tunnel address;
- peer public key;
- endpoint;
- DNS server.

Provision the private key locally:

```text
/run/secrets/qbittorrent-wg-private-key
```

Then enable:

```nix
homeOps.media.downloads.qbittorrent.enable = true;
```

Verify:

```bash
systemctl status qbittorrent-vpn-netns
systemctl status qbittorrent
ip netns exec qbittorrent ip route
ip netns exec qbittorrent nft list ruleset
```
