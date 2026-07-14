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
  calibreWeb = cfg.calibreWeb;
  calibreWebAutomated = cfg.calibreWebAutomated;
in
{
  options.homeOps.media.books = {
    enable = lib.mkEnableOption "books and audiobooks services";
    calibreWebAutomated = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable Calibre-Web-Automated as the default book library manager. This
          is preferred for a fresh NAS because it can initialize an empty Calibre
          library and has explicit network-share handling.
        '';
      };
      image = lib.mkOption {
        type = lib.types.str;
        default = "crocodilestick/calibre-web-automated:v4.0.6";
        description = "Pinned Calibre-Web-Automated container image.";
      };
      webuiPort = lib.mkOption {
        type = lib.types.port;
        default = 8083;
        description = "Localhost-bound Calibre-Web-Automated web UI port.";
      };
    };
    calibreWeb.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable Calibre-Web once the books media directory contains a valid
        Calibre library metadata.db.
      '';
    };
    shelfmark = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      image = lib.mkOption {
        type = lib.types.str;
        default = "ghcr.io/calibrain/shelfmark:v1.3.3";
        description = "Pinned Shelfmark container image.";
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
      {
        assertion = !(calibreWeb.enable && calibreWebAutomated.enable);
        message = "Use either native Calibre-Web or Calibre-Web-Automated, not both.";
      }
    ];

    services.audiobookshelf = {
      enable = true;
      host = "127.0.0.1";
      port = 13378;
    };

    services.calibre-web = lib.mkIf calibreWeb.enable {
      enable = true;
      listen.ip = "127.0.0.1";
      listen.port = 8083;
      group = "media";
      options = {
        calibreLibrary = "${shared.dataRoot}/media/books";
        enableBookUploading = true;
      };
    };

    systemd.services = {
      audiobookshelf.unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      calibre-web = lib.mkIf calibreWeb.enable {
        unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      };
      docker-calibre-web-automated = lib.mkIf calibreWebAutomated.enable {
        unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      };
      docker-shelfmark = lib.mkIf shelfmark.enable {
        unitConfig.RequiresMountsFor = [ shared.dataRoot ];
        after = [
          "home-ops-runtime-secrets.service"
          "prowlarr.service"
        ]
        ++ lib.optionals config.homeOps.media.downloads.qbittorrent.enable [
          "docker-qbittorrent.service"
        ]
        ++ lib.optionals calibreWebAutomated.enable [
          "docker-calibre-web-automated.service"
        ];
        wants = [
          "prowlarr.service"
        ]
        ++ lib.optionals config.homeOps.media.downloads.qbittorrent.enable [
          "docker-qbittorrent.service"
        ]
        ++ lib.optionals calibreWebAutomated.enable [
          "docker-calibre-web-automated.service"
        ];
        requires = [ "home-ops-runtime-secrets.service" ];
      };
    };

    virtualisation.oci-containers.containers.calibre-web-automated = lib.mkIf calibreWebAutomated.enable {
      image = calibreWebAutomated.image;
      autoStart = true;
      environment = {
        PUID = "1000";
        PGID = "1001";
        TZ = config.time.timeZone;
        NETWORK_SHARE_MODE = "true";
        CWA_PORT_OVERRIDE = "8083";
      };
      volumes = [
        "/var/lib/home-ops/calibre-web-automated:/config"
        "${shared.dataRoot}/media/books/imports:/cwa-book-ingest"
        "${shared.dataRoot}/media/books/library:/calibre-library"
      ];
      # Host networking so Tailscale reaches :8083; NixOS firewall gates LAN.
      extraOptions = [ "--network=host" ];
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

        AUDIOBOOK_LIBRARY_URL = "http://127.0.0.1:13378";
        INGEST_DIR = "/books";
        DESTINATION_AUDIOBOOK = "/audiobooks";

        PROWLARR_ENABLED = "true";
        PROWLARR_URL = "http://127.0.0.1:9696";
        PROWLARR_TORRENT_CLIENT = "qbittorrent";
        PROWLARR_TORRENT_ACTION = "keep";

        QBITTORRENT_URL = "http://127.0.0.1:8081";
        QBITTORRENT_CATEGORY = "books";
        QBITTORRENT_CATEGORY_AUDIOBOOK = "audiobooks";
      }
      // lib.optionalAttrs (calibreWeb.enable || calibreWebAutomated.enable) {
        CALIBRE_WEB_URL = "http://127.0.0.1:${toString (
          if calibreWebAutomated.enable then calibreWebAutomated.webuiPort else 8083
        )}";
      };
      volumes = [
        "/var/lib/home-ops/shelfmark:/config"
        "${shared.dataRoot}/media/books/imports:/books"
        "${shared.dataRoot}/media/audiobooks/imports:/audiobooks"
        "${shared.dataRoot}:/data"
      ];
      extraOptions = [ "--network=host" ];
    };
  };
}
