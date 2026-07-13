{
  description = "NixOS home ops configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      disko,
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
          pkgs.git
          pkgs.just
          pkgs.nixfmt
        ];
      };

      nixosConfigurations.media-node = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          ./machines/media-node/configuration.nix
        ];
      };
    };
}
