{ lib, pkgs, ... }:

{
  options.homeOps.tailscaleAddress = lib.mkOption {
    type = lib.types.str;
    description = ''
      This machine's stable Tailscale IPv4 address. Used to bind Docker port
      publishes to the tailnet only when host networking isn't an option
      (e.g. sidecar VPN setups where the container shares another container's
      network namespace). Set per-machine in that machine's configuration.
    '';
  };

  config = {

  time.timeZone = "America/Chicago";

  users = {
    mutableUsers = true;
    users.homeops = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [ "wheel" ];
    };
  };

  environment.systemPackages = [
    pkgs.btop
    pkgs.curl
    pkgs.git
    pkgs.just
    pkgs.vim
  ];

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "homeops"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  };
}
