{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.music;
  shared = config.homeOps.media.shared;
  secretsDir = config.homeOps.secrets.directory;
  beetsConfig = (pkgs.formats.yaml { }).generate "beets-config.yaml" {
    directory = "/data/media/music";
    library = "/var/lib/home-ops/beets/library.db";
    import = {
      incremental = true;
      quiet = true;
      quiet_fallback = "skip";
      write = true;
      copy = false;
      move = false;
      log = "/var/lib/home-ops/beets/import.log";
    };
    plugins = "fetchart embedart";
    fetchart.auto = true;
    embedart = {
      auto = true;
      ifempty = true;
    };
  };
in
{
  options.homeOps.media.music = {
    enable = lib.mkEnableOption "music and podcast services";
    aurral.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable Aurral, a music discovery and request app for Lidarr.
      '';
    };
    aurral.image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/lklynet/aurral:1.76.0";
      description = "Pinned Aurral container image.";
    };
    soulseek.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable the Soulseek acquisition pipeline: slskd (Soulseek client)
        plus Soularr, which searches slskd for Lidarr's wanted albums.
      '';
    };
    soulseek.soularrImage = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/mrusse/soularr:1.2.2";
      description = "Pinned Soularr container image.";
    };
    beets.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable a nightly beets run that tags the music library in place
        (MusicBrainz metadata, cover art fetch/embed). Files are never
        moved or renamed; Lidarr owns layout.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.soulseek.enable -> config.homeOps.secrets.enable;
        message = "homeOps.media.music.soulseek requires homeOps.secrets.enable for slskd credentials.";
      }
    ];

    services.lidarr = {
      enable = true;
      group = "media";
      openFirewall = false;
    };

    services.navidrome = {
      enable = true;
      settings = {
        # TEMP: LAN-bound while testing; back to 127.0.0.1 with the firewall
        # cleanup below.
        Address = "0.0.0.0";
        Port = 4533;
        MusicFolder = "${shared.dataRoot}/media/music";
      };
    };

    # slskd, Soularr, and Lidarr must all see the downloads at the same path
    # string, so everything uses /data/soulseek/... — valid on the host via the
    # /data -> dataRoot symlink from shared.nix, and inside the Soularr
    # container via an equivalent mount.
    services.slskd = lib.mkIf cfg.soulseek.enable {
      enable = true;
      group = "media";
      domain = null;
      openFirewall = true; # soulseek listen port (50300) only, not the web UI
      environmentFile = "${secretsDir}/slskd-env";
      settings = {
        directories = {
          downloads = "/data/soulseek/complete";
          incomplete = "/data/soulseek/incomplete";
        };
        shares.directories = [ "/data/media/music" ];
        shares.filters = [
          "\\.ini$"
          "Thumbs\\.db$"
          "\\.DS_Store$"
        ];
        # Soularr leaves imported downloads behind (Lidarr copies on import);
        # slskd garbage-collects them after 14 days.
        retention.files.complete = 20160;
      };
    };

    # TEMP: slskd web UI (5030), Soularr status UI (8265), and Navidrome
    # (4533) open to the LAN while testing the pipeline; drop these back to
    # tailscale-only once it works.
    networking.firewall.allowedTCPPorts = [
      4533
    ]
    ++ lib.optionals cfg.soulseek.enable [
      5030
      8265
    ];

    systemd.tmpfiles.rules = lib.optionals cfg.soulseek.enable [
      "d ${shared.dataRoot}/soulseek 0775 homeops media -"
      "d ${shared.dataRoot}/soulseek/complete 0775 homeops media -"
      "d ${shared.dataRoot}/soulseek/incomplete 0775 homeops media -"
      "d /var/lib/home-ops/soularr 0775 homeops media -"
    ]
    ++ lib.optionals cfg.beets.enable [
      "d /var/lib/home-ops/beets 0775 homeops media -"
    ];

    systemd.services = {
      lidarr.unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      navidrome.unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      docker-aurral = lib.mkIf cfg.aurral.enable {
        unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      };

      slskd = lib.mkIf cfg.soulseek.enable {
        unitConfig.RequiresMountsFor = [ shared.dataRoot ];
        after = [ "home-ops-runtime-secrets.service" ];
        requires = [ "home-ops-runtime-secrets.service" ];
        # Group-writable downloads so Lidarr (group media) can import and
        # Soularr (1000:1001) can reorganize.
        serviceConfig.UMask = "0002";
      };

      docker-soularr = lib.mkIf cfg.soulseek.enable {
        unitConfig.RequiresMountsFor = [ shared.dataRoot ];
        after = [
          "home-ops-runtime-secrets.service"
          "slskd.service"
          "lidarr.service"
        ];
        requires = [ "home-ops-runtime-secrets.service" ];
        preStart = ''
          lidarr_key="$(< ${secretsDir}/lidarr-api-key)"
          slskd_key="$(< ${secretsDir}/slskd-api-key)"
          sed \
            -e "s|@LIDARR_API_KEY@|$lidarr_key|" \
            -e "s|@SLSKD_API_KEY@|$slskd_key|" \
            ${./config/soularr/config.ini} > /var/lib/home-ops/soularr/config.ini
          chown 1000:1001 /var/lib/home-ops/soularr/config.ini
          chmod 0600 /var/lib/home-ops/soularr/config.ini
        '';
      };

      beets-import = lib.mkIf cfg.beets.enable {
        description = "Tag the music library in place with beets";
        unitConfig.RequiresMountsFor = [ shared.dataRoot ];
        serviceConfig = {
          Type = "oneshot";
          User = "homeops";
          Group = "media";
          UMask = "0002";
          ExecStart = "${pkgs.beets}/bin/beet -c ${beetsConfig} import -q /data/media/music";
        };
      };
    };

    systemd.timers.beets-import = lib.mkIf cfg.beets.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "03:15";
        Persistent = true;
      };
    };

    virtualisation.oci-containers.containers.aurral = lib.mkIf cfg.aurral.enable {
      image = cfg.aurral.image;
      autoStart = true;
      ports = [ "127.0.0.1:8098:3001" ];
      environment = {
        PUID = "1000";
        PGID = "1001";
        TZ = config.time.timeZone;
        DOWNLOAD_FOLDER = "/app/downloads";
      };
      volumes = [
        "/var/lib/home-ops/aurral:/app/backend/data"
        "${shared.dataRoot}/media/music/aurral:/app/downloads"
        "${shared.dataRoot}/media/music:/data:ro"
      ];
      extraOptions = [ "--add-host=host.docker.internal:host-gateway" ];
    };

    # Host networking so Soularr reaches Lidarr (127.0.0.1:8686) and slskd
    # (127.0.0.1:5030) directly; its status web UI ends up on host port 8265,
    # reachable over tailscale0 only (LAN is firewalled).
    virtualisation.oci-containers.containers.soularr = lib.mkIf cfg.soulseek.enable {
      image = cfg.soulseek.soularrImage;
      autoStart = true;
      user = "1000:1001";
      environment = {
        TZ = config.time.timeZone;
        SCRIPT_INTERVAL = "900";
      };
      volumes = [
        # The image reads /data/config.ini; nesting the soulseek mount under
        # it keeps the /data/soulseek/... path convention intact.
        "/var/lib/home-ops/soularr:/data"
        "${shared.dataRoot}/soulseek:/data/soulseek"
      ];
      extraOptions = [ "--network=host" ];
    };
  };
}
