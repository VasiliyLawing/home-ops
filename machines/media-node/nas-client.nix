{ config, lib, pkgs, ... }:

let
  cfg = config.homeOps.nas;
in
{
  options.homeOps.nas = {
    enable = lib.mkEnableOption "the NAS media NFS mount";
    host = lib.mkOption {
      type = lib.types.str;
      default = "REPLACE_WITH_NAS_IP";
      description = "NAS IP address or stable DNS name.";
    };
    export = lib.mkOption {
      type = lib.types.str;
      default = "/volume1/media-stack";
      description = "NFS export path on the NAS.";
    };
    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nas/data";
      description = "Local mount point for media stack data.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.host != "REPLACE_WITH_NAS_IP";
        message = "Set homeOps.nas.host to the NAS address before enabling the mount.";
      }
    ];

    environment.systemPackages = [ pkgs.nfs-utils ];

    fileSystems.${cfg.mountPoint} = {
      device = "${cfg.host}:${cfg.export}";
      fsType = "nfs";
      options = [
        "nfsvers=4.1"
        "x-systemd.automount"
        "noauto"
        "nofail"
      ];
    };
  };
}
