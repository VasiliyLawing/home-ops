# CI/CD

The repo includes two GitHub Actions:

- `Nix CI`: validates the flake and dry-runs the `media-node` system build.
- `Deploy media-node`: manual deploy button that joins Tailscale and runs
  `clan machines update media-node`.

## Required GitHub secrets

Store these as repository or environment secrets:

```text
TS_OAUTH_CLIENT_ID
TS_AUDIENCE
CLAN_SSH_PRIVATE_KEY
```

`CLAN_SSH_PRIVATE_KEY` should contain the private deploy key matching the public
key configured in `modules/common/base.nix`.

## Tailscale policy

The CI identity needs SSH/network access to `media-node` on TCP port 22.

The deploy workflow assumes `media-node` resolves through MagicDNS. If not,
update `clan.core.networking.targetHost` in:

```text
machines/media-node/configuration.nix
```
