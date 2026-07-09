set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

machine := "media-node"

fmt:
    nix fmt

check:
    nix flake check --no-build

build:
    nix build .#nixosConfigurations.{{machine}}.config.system.build.toplevel --dry-run

deploy:
    clan machines update {{machine}}
