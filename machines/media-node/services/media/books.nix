{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.books;
  shared = config.homeOps.media.shared;
  shelfmark = cfg.shelfmark;
in
{
  options.homeOps.media.books = {
    enable = lib.mkEnableOption "books and audiobooks services";
    shelfmark = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      image = lib.mkOption {
        type = lib.types.str;
        default = "ghcr.io/calibrain/shelfmark:latest";
        description = "Shelfmark container image. Pin this before real deployment.";
      };
      webuiPort = lib.mkOption {
        type = lib.types.port;
        default = 8099;
        description = "Localhost-bound Shelfmark web UI port.";
      };
      environmentFile = lib.mkOption {
        type = lib.types.str;
        default = "${config.homeOps.secrets.directory}/shelfmark-env";
        description = "Host-local env file containing Shelfmark Prowlarr/qBittorrent secrets.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !shelfmark.enable || config.homeOps.secrets.enable;
        message = "Shelfmark qBittorrent/Prowlarr wiring requires homeOps.secrets.enable.";
      }
      {
        assertion = !shelfmark.enable || config.homeOps.media.moviesTv.enable;
        message = "Shelfmark Prowlarr wiring requires homeOps.media.moviesTv.enable.";
      }
    ];

    services.audiobookshelf = {
      enable = true;
      host = "127.0.0.1";
      port = 13378;
    };

    services.calibre-web = {
      enable = true;
      listen.ip = "127.0.0.1";
      listen.port = 8083;
      group = "media";
      options = {
        calibreLibrary = "${shared.dataRoot}/media/books";
        enableBookUploading = true;
      };
    };

    environment.systemPackages = lib.mkIf shelfmark.enable [ pkgs.shelfmark ];

    systemd.services = {
      audiobookshelf.unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      calibre-web.unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      docker-shelfmark = lib.mkIf shelfmark.enable {
        unitConfig.RequiresMountsFor = [ shared.dataRoot ];
        after = [
          "home-ops-runtime-secrets.service"
          "prowlarr.service"
        ]
        ++ lib.optionals config.homeOps.media.downloads.qbittorrent.enable [
          "docker-qbittorrent.service"
        ];
        wants = [
          "prowlarr.service"
        ]
        ++ lib.optionals config.homeOps.media.downloads.qbittorrent.enable [
          "docker-qbittorrent.service"
        ];
        requires = [ "home-ops-runtime-secrets.service" ];
      };
    };

    virtualisation.oci-containers.containers.shelfmark = lib.mkIf shelfmark.enable {
      image = shelfmark.image;
      autoStart = true;
      environmentFiles = [ shelfmark.environmentFile ];
      environment = {
        PUID = "1000";
        PGID = "1001";
        TZ = config.time.timeZone;
        DOCKERMODE = "true";

        FLASK_HOST = "127.0.0.1";
        FLASK_PORT = toString shelfmark.webuiPort;
        SEARCH_MODE = "universal";

        CALIBRE_WEB_URL = "http://127.0.0.1:8083";
        AUDIOBOOK_LIBRARY_URL = "http://127.0.0.1:13378";
        INGEST_DIR = "/books";
        DESTINATION_AUDIOBOOK = "/audiobooks";

        PROWLARR_ENABLED = "true";
        PROWLARR_URL = "http://127.0.0.1:9696";
        PROWLARR_TORRENT_CLIENT = "qbittorrent";
        PROWLARR_TORRENT_ACTION = "keep";

        QBITTORRENT_URL = "http://127.0.0.1:8080";
        QBITTORRENT_CATEGORY = "books";
        QBITTORRENT_CATEGORY_AUDIOBOOK = "audiobooks";
      };
      volumes = [
        "/var/lib/home-ops/shelfmark:/config"
        "${shared.dataRoot}/media/books/imports:/books"
        "${shared.dataRoot}/media/audiobooks/imports:/audiobooks"
        "${shared.dataRoot}:/data"
      ];
      extraOptions = [
        "--pull=newer"
        "--network=host"
      ];
    };
  };
}
