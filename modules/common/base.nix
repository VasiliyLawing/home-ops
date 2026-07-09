{ pkgs, ... }:

let
  adminSshKeys = [
    "ssh-ed25519 REPLACE_WITH_PUBLIC_SSH_KEY home-ops-admin"
  ];
in
{
  networking = {
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      trustedInterfaces = [ "tailscale0" ];
    };
  };

  time.timeZone = "America/Chicago";

  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };
    tailscale.enable = true;
  };

  users = {
    mutableUsers = true;
    groups.media.gid = 1001;
    users.homeops = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [
        "media"
        "networkmanager"
        "wheel"
      ];
      openssh.authorizedKeys.keys = adminSshKeys;
    };
    users.root.openssh.authorizedKeys.keys = adminSshKeys;
  };

  environment.systemPackages = [
    pkgs.btop
    pkgs.curl
    pkgs.git
    pkgs.just
    pkgs.sops
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

  systemd.tmpfiles.rules = [ "d /srv/home-ops/backups 0775 homeops media -" ];
}
