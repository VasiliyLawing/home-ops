{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.qbitManage;
  shared = config.homeOps.media.shared;
  runtimeConfigDir = "/var/lib/home-ops/qbit-manage/config";
in
{
  options.homeOps.media.qbitManage = {
    enable = lib.mkEnableOption "qBit Manage qBittorrent category/tag/cleanup sync";
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/stuffanthings/qbit_manage:latest";
      description = "qBit Manage container image. Pin this before real deployment.";
    };
    configDir = lib.mkOption {
      type = lib.types.path;
      default = ./config/qbit-manage;
      description = "Directory containing non-secret qBit Manage config.yml.";
    };
    credentialsEnvFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.homeOps.secrets.directory}/qbittorrent-env";
      description = "Env file containing QBIT_USER and QBIT_PASS for qBittorrent WebUI auth.";
    };
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Systemd calendar expression for scheduled qBit Manage runs.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.downloads.qbittorrent.enable;
        message = "homeOps.media.qbitManage requires homeOps.media.downloads.qbittorrent.enable.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.qbitManage requires homeOps.secrets.enable.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/home-ops/qbit-manage 0775 homeops media -"
      "d ${runtimeConfigDir} 0775 homeops media -"
      "d ${runtimeConfigDir}/logs 0775 homeops media -"
    ];

    systemd.services.qbit-manage-sync = {
      description = "Sync qBit Manage categories, tags, and cleanup rules";
      unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      after = [
        "docker.service"
        "home-ops-runtime-secrets.service"
        "docker-gluetun.service"
        "docker-qbittorrent.service"
      ];
      wants = [
        "docker.service"
        "home-ops-runtime-secrets.service"
        "docker-gluetun.service"
        "docker-qbittorrent.service"
      ];
      requires = [
        "home-ops-runtime-secrets.service"
        "docker-qbittorrent.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/install -m 0644 -o homeops -g media ${cfg.configDir}/config.yml ${runtimeConfigDir}/config.yml";
        ExecStart = "${pkgs.docker}/bin/docker run --rm --name qbit-manage-sync --network host --env-file ${cfg.credentialsEnvFile} --env TZ=${config.time.timeZone} --env PUID=1000 --env PGID=1001 --env QBT_RUN=true --env QBT_CONFIG_DIR=/config --env QBT_LOGFILE=/config/logs/qbit_manage.log --env QBT_WEB_SERVER=false --volume ${runtimeConfigDir}:/config:rw --volume ${shared.dataRoot}/torrents:/data/torrents:rw ${cfg.image}";
      };
    };

    systemd.timers.qbit-manage-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
      };
    };
  };
}
