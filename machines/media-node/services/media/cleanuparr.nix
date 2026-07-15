{ config, lib, ... }:

let
  cfg = config.homeOps.media.cleanuparr;
in
{
  options.homeOps.media.cleanuparr = {
    enable = lib.mkEnableOption "Cleanuparr — automatic cleanup for stalled/malicious torrents";
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/cleanuparr/cleanuparr:2.9.16";
    };
    port = lib.mkOption {
      type = lib.types.int;
      default = 11011;
      description = "Port Cleanuparr binds on the host (host networking). Tailscale-reachable; LAN blocked by the firewall.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/cleanuparr";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.cleanuparr = {
      image = cfg.image;
      volumes = [ "${cfg.dataDir}:/config" ];
      environment = {
        TZ = config.time.timeZone;
        PORT = toString cfg.port;
      };
      # Host networking: NixOS firewall's trustedInterfaces=tailscale0 handles
      # gating, and http://localhost:8989 inside the container hits Sonarr.
      extraOptions = [ "--network=host" ];
    };
  };
}
