{
  imports = [
    ../../shared
    ./host.nix
    ./services/neovim.nix
  ];

  networking.hostName = "workstation-wsl";

  homeOps.dev.neovim.enable = true;

  system.stateVersion = "26.05";
}
