# CI/CD

The repo includes two GitHub Actions:

- `Nix CI`: validates the flake and fully builds both machine closures.
- `Deploy media-node`: manual deploy button that joins Tailscale and runs a
  remote `nixos-rebuild switch` against `media-node`.

## Required GitHub secrets

Store these as repository or environment secrets:

```text
TS_AUTHKEY
CLAN_SSH_PRIVATE_KEY
```

`CLAN_SSH_PRIVATE_KEY` should contain the private deploy key matching the public
key configured in `machines/media-node/host.nix`.

## Tailscale policy

The Tailscale auth key should be ephemeral and tagged for CI, for example
`tag:ci`. The CI identity needs SSH/network access to `media-node` on TCP port
22.

The deploy workflow assumes `media-node` resolves through MagicDNS or the
runner's SSH config. If not, update the deploy workflow target host in:

```text
.github/workflows/deploy.yml
```
