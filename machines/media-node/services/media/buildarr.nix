{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.buildarr;
  runtimeConfigDir = "/var/lib/home-ops/buildarr/config";
in
{
  options.homeOps.media.buildarr = {
    enable = lib.mkEnableOption "Buildarr app wiring sync";
    image = lib.mkOption {
      type = lib.types.str;
      default = "callum027/buildarr:latest";
      description = "Buildarr container image. Pin this before real deployment.";
    };
    configDir = lib.mkOption {
      type = lib.types.path;
      default = ./config/buildarr;
      description = "Directory containing non-secret Buildarr YAML.";
    };
    secretsFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.homeOps.secrets.directory}/buildarr-secret.yml";
      description = "Host-local Buildarr secrets include generated from runtime secrets.";
    };
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Systemd calendar expression for scheduled Buildarr syncs.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.moviesTv.enable;
        message = "homeOps.media.buildarr requires homeOps.media.moviesTv.enable.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.buildarr requires homeOps.secrets.enable.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/home-ops/buildarr 0775 homeops media -"
      "d ${runtimeConfigDir} 0775 homeops media -"
    ];

    systemd.services.buildarr-sync = {
      description = "Sync Buildarr app wiring";
      after = [
        "docker.service"
        "home-ops-runtime-secrets.service"
        "sonarr.service"
        "radarr.service"
        "prowlarr.service"
      ];
      wants = [
        "docker.service"
        "home-ops-runtime-secrets.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/install -m 0644 -o homeops -g media ${cfg.configDir}/buildarr.yml ${runtimeConfigDir}/buildarr.yml";
        ExecStart = "${pkgs.docker}/bin/docker run --rm --name buildarr-sync --network host --env TZ=${config.time.timeZone} --env PUID=1000 --env PGID=1001 --volume ${runtimeConfigDir}:/config:ro --volume ${cfg.secretsFile}:/config/secrets.yml:ro ${cfg.image} run";
      };
    };

    systemd.timers.buildarr-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
      };
    };
  };
}
