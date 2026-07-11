set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

machine := "media-node"
workstation := "workstation-wsl"

fmt:
    nix fmt

check:
    nix flake check --no-build

build:
    nix build .#nixosConfigurations.{{machine}}.config.system.build.toplevel --dry-run

build-workstation:
    nix build .#nixosConfigurations.{{workstation}}.config.system.build.toplevel --dry-run

deploy:
    clan machines update {{machine}}

switch-workstation:
    sudo nixos-rebuild switch --flake .#{{workstation}}
