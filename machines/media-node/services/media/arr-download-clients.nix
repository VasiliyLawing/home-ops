{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.arrDownloadClients;
  downloads = config.homeOps.media.downloads;
  bootstrapArrDownloadClients = pkgs.buildGoModule {
    pname = "home-ops-bootstrap-arr-download-clients";
    version = "0.1.0";
    src = ../../scripts/runtime-secrets/arr-download-client-bootstrap;
    vendorHash = null;
    env.CGO_ENABLED = "0";
    postInstall = ''
      mv "$out/bin/arr-download-client-bootstrap" "$out/bin/home-ops-bootstrap-arr-download-clients"
    '';
  };
in
{
  options.homeOps.media.arrDownloadClients = {
    enable = lib.mkEnableOption "Sonarr/Radarr qBittorrent download-client bootstrap";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.moviesTv.enable;
        message = "homeOps.media.arrDownloadClients requires homeOps.media.moviesTv.enable.";
      }
      {
        assertion = downloads.qbittorrent.enable;
        message = "homeOps.media.arrDownloadClients requires qBittorrent.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.arrDownloadClients requires homeOps.secrets.enable.";
      }
    ];

    systemd.services.home-ops-arr-download-clients = {
      description = "Bootstrap Sonarr/Radarr qBittorrent download clients";
      wantedBy = [ "multi-user.target" ];
      after = [
        "home-ops-runtime-secrets.service"
        "sonarr.service"
        "radarr.service"
        "docker-qbittorrent.service"
      ]
      ++ lib.optionals downloads.qbittorrent.bootstrapConfig [
        "home-ops-qbittorrent-config.service"
      ];
      wants = [
        "sonarr.service"
        "radarr.service"
        "docker-qbittorrent.service"
      ]
      ++ lib.optionals downloads.qbittorrent.bootstrapConfig [
        "home-ops-qbittorrent-config.service"
      ];
      requires = [ "home-ops-runtime-secrets.service" ];
      environment = {
        HOME_OPS_QBIT_USERNAME_FILE = "${config.homeOps.secrets.directory}/qbittorrent-webui-username";
        HOME_OPS_QBIT_PASSWORD_FILE = "${config.homeOps.secrets.directory}/qbittorrent-webui-password";
        HOME_OPS_SONARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/sonarr-api-key";
        HOME_OPS_RADARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/radarr-api-key";
        HOME_OPS_QBIT_HOST = "127.0.0.1";
        HOME_OPS_QBIT_PORT = toString downloads.qbittorrent.webuiPort;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${bootstrapArrDownloadClients}/bin/home-ops-bootstrap-arr-download-clients";
        RemainAfterExit = true;
      };
    };
  };
}
