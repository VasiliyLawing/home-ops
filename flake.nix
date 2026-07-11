{
  description = "Clan-managed NixOS home ops configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    disko.url = "github:nix-community/disko";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      clan-core,
      disko,
      nixos-wsl,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      formatter.${system} = pkgs.nixfmt;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          clan-core.packages.${system}.clan-cli
          pkgs.git
          pkgs.just
          pkgs.nixfmt
        ];
      };

      clan = {
        meta.name = "home-ops";
        machines.media-node = {
          nixpkgs.hostPlatform = system;
          imports = [ ./machines/media-node/configuration.nix ];
        };
        machines.workstation-wsl = {
          nixpkgs.hostPlatform = system;
          imports = [ ./machines/workstation-wsl/configuration.nix ];
        };
      };

      nixosConfigurations.media-node = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          clan-core.nixosModules.clanCore
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          {
            clan.core.settings = {
              directory = self;
              machine.name = "media-node";
            };
          }
          ./machines/media-node/configuration.nix
        ];
      };

      nixosConfigurations.workstation-wsl = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          clan-core.nixosModules.clanCore
          nixos-wsl.nixosModules.default
          {
            clan.core.settings = {
              directory = self;
              machine.name = "workstation-wsl";
            };
          }
          ./machines/workstation-wsl/configuration.nix
        ];
      };
    };
}
