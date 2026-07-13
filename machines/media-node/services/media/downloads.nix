{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.downloads;
  shared = config.homeOps.media.shared;
  gluetunEnabled = cfg.gluetun.enable || cfg.qbittorrent.enable;
  bootstrapQbittorrentConfig = pkgs.buildGoModule {
    pname = "home-ops-bootstrap-qbittorrent-config";
    version = "0.1.0";
    src = ../../scripts/runtime-secrets/qbittorrent-bootstrap;
    vendorHash = null;
    env.CGO_ENABLED = "0";
    postInstall = ''
      mv "$out/bin/qbittorrent-bootstrap" "$out/bin/home-ops-bootstrap-qbittorrent-config"
    '';
  };
  bootstrapQbittorrentAPI = pkgs.buildGoModule {
    pname = "home-ops-bootstrap-qbittorrent-api";
    version = "0.1.0";
    src = ../../scripts/runtime-secrets/qbittorrent-api-bootstrap;
    vendorHash = null;
    env.CGO_ENABLED = "0";
    postInstall = ''
      if [ -x "$out/bin/qbittorrent-api-bootstrap" ]; then
        mv "$out/bin/qbittorrent-api-bootstrap" "$out/bin/home-ops-bootstrap-qbittorrent-api"
      elif [ -x "$out/bin/home-ops-qbittorrent-api-bootstrap" ]; then
        mv "$out/bin/home-ops-qbittorrent-api-bootstrap" "$out/bin/home-ops-bootstrap-qbittorrent-api"
      else
        echo "Could not find qBittorrent API bootstrap binary. Available binaries:" >&2
        ls -la "$out/bin" >&2
        exit 1
      fi
    '';
  };
in
{
  options.homeOps.media.downloads = {
    sabnzbd.enable = lib.mkEnableOption "SABnzbd directly on the host";

    gluetun = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the provider-neutral VPN container used by qBittorrent.";
      };
      image = lib.mkOption {
        type = lib.types.str;
        default = "ghcr.io/qdm12/gluetun:v3.41.1";
        description = "Pinned Gluetun container image.";
      };
      environmentFile = lib.mkOption {
        type = lib.types.str;
        default = "${config.homeOps.secrets.directory}/gluetun-env";
        description = "Host-local env file containing VPN provider settings and secrets.";
      };
      configDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/gluetun";
        description = "Local SSD-backed Gluetun state directory.";
      };
    };

    qbittorrent = {
      enable = lib.mkEnableOption "qBittorrent container sharing Gluetun's VPN network namespace";
      image = lib.mkOption {
        type = lib.types.str;
        default = "lscr.io/linuxserver/qbittorrent:5.2.3";
        description = "Pinned qBittorrent container image.";
      };
      webuiPort = lib.mkOption {
        type = lib.types.port;
        default = 8081;
      };
      torrentingPort = lib.mkOption {
        type = lib.types.port;
        default = 6881;
      };
      savePath = lib.mkOption {
        type = lib.types.str;
        default = "/data/torrents/complete";
        description = "Default completed-download path inside qBittorrent.";
      };
      incompletePath = lib.mkOption {
        type = lib.types.str;
        default = "/data/torrents/incomplete";
        description = "Incomplete-download path inside qBittorrent.";
      };
      configDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/qbittorrent";
        description = "Local SSD-backed qBittorrent config/state directory.";
      };
      bootstrapConfig = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Seed qBittorrent WebUI credentials before the container starts.";
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = !cfg.qbittorrent.enable || gluetunEnabled;
        message = "qBittorrent requires Gluetun so it cannot run outside the VPN namespace.";
      }
      {
        assertion =
          !(cfg.qbittorrent.enable && cfg.qbittorrent.bootstrapConfig) || config.homeOps.secrets.enable;
        message = "qBittorrent credential bootstrap requires homeOps.secrets.enable.";
      }
    ];

    services.sabnzbd = lib.mkIf cfg.sabnzbd.enable {
      enable = true;
      group = "media";
      openFirewall = false;
    };

    boot.kernelModules = lib.mkIf gluetunEnabled [ "tun" ];

    systemd.tmpfiles.rules = lib.mkIf gluetunEnabled [
      "d ${cfg.gluetun.configDir} 0700 root root -"
      "d ${cfg.qbittorrent.configDir} 0775 homeops media -"
      "d ${cfg.qbittorrent.configDir}/qBittorrent 0775 homeops media -"
    ];

    systemd.services.home-ops-qbittorrent-config =
      lib.mkIf (cfg.qbittorrent.enable && cfg.qbittorrent.bootstrapConfig)
        {
          description = "Seed qBittorrent WebUI credentials from Home Ops runtime secrets";
          wantedBy = [ "multi-user.target" ];
          after = [ "home-ops-runtime-secrets.service" ];
          requires = [ "home-ops-runtime-secrets.service" ];
          before = [ "docker-qbittorrent.service" ];
          environment = {
            HOME_OPS_QBIT_CONFIG_FILE = "${cfg.qbittorrent.configDir}/qBittorrent/qBittorrent.conf";
            HOME_OPS_QBIT_USERNAME_FILE = "${config.homeOps.secrets.directory}/qbittorrent-webui-username";
            HOME_OPS_QBIT_PASSWORD_FILE = "${config.homeOps.secrets.directory}/qbittorrent-webui-password";
            HOME_OPS_QBIT_OWNER = "homeops";
            HOME_OPS_QBIT_GROUP = "media";
            HOME_OPS_QBIT_WEBUI_PORT = toString cfg.qbittorrent.webuiPort;
            HOME_OPS_QBIT_TORRENTING_PORT = toString cfg.qbittorrent.torrentingPort;
            HOME_OPS_QBIT_SAVE_PATH = cfg.qbittorrent.savePath;
            HOME_OPS_QBIT_TEMP_PATH = cfg.qbittorrent.incompletePath;
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${bootstrapQbittorrentConfig}/bin/home-ops-bootstrap-qbittorrent-config";
            RemainAfterExit = true;
          };
        };

    systemd.services.docker-qbittorrent =
      lib.mkIf (cfg.qbittorrent.enable && cfg.qbittorrent.bootstrapConfig)
        {
          unitConfig.RequiresMountsFor = [ shared.dataRoot ];
          after = [ "home-ops-qbittorrent-config.service" ];
          requires = [ "home-ops-qbittorrent-config.service" ];
        };

    systemd.services.home-ops-qbittorrent-api-config =
      lib.mkIf (cfg.qbittorrent.enable && cfg.qbittorrent.bootstrapConfig)
        {
          description = "Configure live qBittorrent Web API paths and categories";
          wantedBy = [ "multi-user.target" ];
          after = [
            "home-ops-runtime-secrets.service"
            "docker-qbittorrent.service"
          ];
          wants = [ "docker-qbittorrent.service" ];
          requires = [
            "home-ops-runtime-secrets.service"
            "docker-qbittorrent.service"
          ];
          environment = {
            HOME_OPS_QBIT_BASE_URL = "http://localhost:${toString cfg.qbittorrent.webuiPort}";
            HOME_OPS_QBIT_USERNAME_FILE = "${config.homeOps.secrets.directory}/qbittorrent-webui-username";
            HOME_OPS_QBIT_PASSWORD_FILE = "${config.homeOps.secrets.directory}/qbittorrent-webui-password";
            HOME_OPS_QBIT_SAVE_PATH = cfg.qbittorrent.savePath;
            HOME_OPS_QBIT_TEMP_PATH = cfg.qbittorrent.incompletePath;
            HOME_OPS_QBIT_TORRENTING_PORT = toString cfg.qbittorrent.torrentingPort;
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${bootstrapQbittorrentAPI}/bin/home-ops-bootstrap-qbittorrent-api";
            RemainAfterExit = true;
          };
        };

    systemd.services.sabnzbd = lib.mkIf cfg.sabnzbd.enable {
      unitConfig.RequiresMountsFor = [ shared.dataRoot ];
    };

    virtualisation.oci-containers.containers = {
      gluetun = lib.mkIf gluetunEnabled {
        image = cfg.gluetun.image;
        autoStart = true;
        environmentFiles = [ cfg.gluetun.environmentFile ];
        volumes = [
          "${cfg.gluetun.configDir}:/gluetun"
        ];
        ports = [
          "127.0.0.1:${toString cfg.qbittorrent.webuiPort}:${toString cfg.qbittorrent.webuiPort}/tcp"
        ];
        extraOptions = [
          "--cap-add=NET_ADMIN"
          "--device=/dev/net/tun:/dev/net/tun"
        ];
      };

      qbittorrent = lib.mkIf cfg.qbittorrent.enable {
        image = cfg.qbittorrent.image;
        autoStart = true;
        dependsOn = [ "gluetun" ];
        environment = {
          PUID = "1000";
          PGID = "1001";
          UMASK = "002";
          WEBUI_PORT = toString cfg.qbittorrent.webuiPort;
          TORRENTING_PORT = toString cfg.qbittorrent.torrentingPort;
        };
        volumes = [
          "${cfg.qbittorrent.configDir}:/config"
          "${shared.dataRoot}:/data"
        ];
        extraOptions = [
          "--network=container:gluetun"
        ];
      };
    };
  };
}
