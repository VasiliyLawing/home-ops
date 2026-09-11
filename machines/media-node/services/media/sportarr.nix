{ config, lib, ... }:

let
  cfg = config.homeOps.media.sportarr;
  shared = config.homeOps.media.shared;
in
{
  options.homeOps.media.sportarr = {
    enable = lib.mkEnableOption "Sportarr — sports event PVR (Sonarr fork)";
    image = lib.mkOption {
      type = lib.types.str;
      default = "sportarr/sportarr:4.1.7.1117";
      description = "Pinned Sportarr container image.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/home-ops/sportarr";
      description = "Local Sportarr config/database directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = shared.enable;
        message = "homeOps.media.sportarr requires homeOps.media.shared.enable for the NAS-backed /data root.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0775 homeops media -"
    ];

    # Same NAS-mount guard as Sonarr/Radarr: never start against a missing /data.
    systemd.services.docker-sportarr.unitConfig.RequiresMountsFor = [ shared.dataRoot ];

    virtualisation.oci-containers.containers.sportarr = {
      image = cfg.image;
      autoStart = true;
      environment = {
        PUID = "1000";
        PGID = "1001";
        UMASK = "002";
        TZ = config.time.timeZone;
      };
      volumes = [
        "${cfg.dataDir}:/config"
        "${shared.dataRoot}:/data"
      ];
      # Host networking on Sportarr's fixed port 1867: Prowlarr/qBittorrent/
      # SABnzbd are reachable at plain 127.0.0.1 from inside the container, and
      # trustedInterfaces=tailscale0 gates the UI (LAN blocked by the firewall).
      # Indexer + download-client wiring is done once in the UI;
      # ponytail: codify via the Arr bootstrappers once the API is confirmed
      # Sonarr-compatible.
      extraOptions = [ "--network=host" ];
    };
  };
}
