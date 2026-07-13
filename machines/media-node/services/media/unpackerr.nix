{
  config,
  lib,
  ...
}:

let
  cfg = config.homeOps.media.unpackerr;
  shared = config.homeOps.media.shared;
in
{
  options.homeOps.media.unpackerr = {
    enable = lib.mkEnableOption "Unpackerr archive extraction for completed downloads";
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/unpackerr/unpackerr:0.15.2";
      description = "Pinned Unpackerr container image.";
    };
    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/home-ops/unpackerr";
      description = "Local Unpackerr config/state directory.";
    };
    interval = lib.mkOption {
      type = lib.types.str;
      default = "2m";
      description = "How often Unpackerr checks Arr applications for archives to extract.";
    };
    startDelay = lib.mkOption {
      type = lib.types.str;
      default = "10m";
      description = "Delay before extracting newly discovered archives.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.moviesTv.enable;
        message = "homeOps.media.unpackerr requires homeOps.media.moviesTv.enable.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.unpackerr requires homeOps.secrets.enable.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.configDir} 0775 homeops media -"
    ];

    systemd.services.docker-unpackerr = {
      unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      after = [
        "home-ops-runtime-secrets.service"
        "sonarr.service"
        "radarr.service"
      ];
      wants = [
        "sonarr.service"
        "radarr.service"
      ];
      requires = [ "home-ops-runtime-secrets.service" ];
    };

    virtualisation.oci-containers.containers.unpackerr = {
      image = cfg.image;
      autoStart = true;
      environment = {
        TZ = config.time.timeZone;
        UN_DEBUG = "false";
        UN_INTERVAL = cfg.interval;
        UN_START_DELAY = cfg.startDelay;
        UN_SONARR_0_URL = "http://127.0.0.1:8989";
        UN_SONARR_0_PATHS_0 = "/data/torrents/complete/tv";
        UN_RADARR_0_URL = "http://127.0.0.1:7878";
        UN_RADARR_0_PATHS_0 = "/data/torrents/complete/movies";
      };
      environmentFiles = [ "${config.homeOps.secrets.directory}/unpackerr-env" ];
      volumes = [
        "${cfg.configDir}:/config"
        "${shared.dataRoot}:/data"
      ];
      extraOptions = [
        "--network=host"
        "--user=1000:1001"
      ];
    };
  };
}
