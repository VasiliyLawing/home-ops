{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.configarr;
  runtimeConfigDir = "/var/lib/home-ops/configarr/config";
in
{
  options.homeOps.media.configarr = {
    enable = lib.mkEnableOption "Configarr Sonarr/Radarr quality profile sync";
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/raydak-labs/configarr:latest";
      description = "Configarr container image. Pin this before real deployment.";
    };
    configDir = lib.mkOption {
      type = lib.types.path;
      default = ./config/configarr;
      description = "Directory containing Configarr config.yml.";
    };
    reposDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/home-ops/configarr/repos";
      description = "Writable cache directory for Configarr template repositories.";
    };
    apiKeysEnvFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.homeOps.secrets.directory}/arr-api-keys.env";
      description = "Host-local env file containing Sonarr/Radarr API keys for Configarr.";
    };
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Systemd calendar expression for scheduled Configarr syncs.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.moviesTv.enable;
        message = "homeOps.media.configarr requires homeOps.media.moviesTv.enable.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.configarr requires homeOps.secrets.enable.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/home-ops/configarr 0775 homeops media -"
      "d ${runtimeConfigDir} 0775 homeops media -"
      "d ${cfg.reposDir} 0775 homeops media -"
    ];

    systemd.services.configarr-sync = {
      description = "Sync Configarr Sonarr/Radarr quality profiles";
      after = [
        "docker.service"
        "home-ops-runtime-secrets.service"
        "sonarr.service"
        "radarr.service"
      ];
      wants = [
        "docker.service"
        "home-ops-runtime-secrets.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = cfg.apiKeysEnvFile;
        ExecStartPre = "${pkgs.coreutils}/bin/install -m 0644 -o homeops -g media ${cfg.configDir}/config.yml ${runtimeConfigDir}/config.yml";
        ExecStart = "${pkgs.docker}/bin/docker run --rm --name configarr-sync --network host --env TZ=${config.time.timeZone} --env SONARR_API_KEY --env RADARR_API_KEY --volume ${runtimeConfigDir}:/app/config:ro --volume ${cfg.reposDir}:/app/repos ${cfg.image}";
      };
    };

    systemd.timers.configarr-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
      };
    };
  };
}
