{ lib, pkgs, ... }:

let
  adminSshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ+yCotEev0DvxbeVef5seO6fINjX1AkcI/GzTIgmLrn home-ops-admin"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC1/Rr8KokJGAWcXaeWN9p3MBl8hvRBVqbcvtLPP/MQI github-actions-home-ops-deploy"
  ];
in
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "unrar" ];

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [ "amd_pstate=active" ];
    initrd.availableKernelModules = [
      "nvme"
      "sd_mod"
      "usb_storage"
      "usbhid"
      "xhci_pci"
    ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  hardware = {
    cpu.amd.updateMicrocode = true;
    graphics = {
      enable = true;
      enable32Bit = true;
    };
  };

  networking = {
    networkmanager = {
      enable = true;
      unmanaged = [ "interface-name:enp3s0" ];
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        80
        443
      ];
      trustedInterfaces = [ "tailscale0" ];
    };
  };

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
    groups.media.gid = 1001;
    users.homeops = {
      extraGroups = [
        "media"
        "networkmanager"
        "render"
        "video"
      ];
      openssh.authorizedKeys.keys = adminSshKeys;
    };
    users.root.openssh.authorizedKeys.keys = adminSshKeys;
  };

  environment.systemPackages = [
    pkgs.libva-utils
    pkgs.sops
  ];

  systemd = {
    network = {
      enable = true;
      networks."10-nas-direct" = {
        matchConfig.Name = "enp3s0";
        address = [ "10.10.10.1/24" ];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
      };
    };

    tmpfiles.rules = [ "d /srv/home-ops/backups 0775 homeops media -" ];
  };
}
