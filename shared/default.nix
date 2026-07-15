{ pkgs, ... }:

{
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
}
