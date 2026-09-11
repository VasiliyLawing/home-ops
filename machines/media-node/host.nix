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

  # No disk swap by design (single NVMe, ext4). Jellyfin transcode buffers
  # have peaked above 20G of 28G; zram gives the OOM killer headroom.
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  hardware = {
    # amdgpu (and every other device needing blobs) fails to probe without
    # this — no /dev/dri render node means no VAAPI transcoding.
    enableRedistributableFirmware = true;
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
    # 22 comes from services.openssh.openFirewall (default true); 1919/2929
    # are opened by the ingress module when it is enabled.
    firewall = {
      enable = true;
      trustedInterfaces = [ "tailscale0" ];
      # LAN scanners were filling the journal with refused-packet lines.
      logRefusedConnections = false;
    };
  };

  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        # NixOS default is true; with PAM that is a second password path.
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };
    tailscale.enable = true;
    # Containers log to journald on NixOS; uncapped it had reached 2.6G.
    journald.settings.Journal.SystemMaxUse = "1G";
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
