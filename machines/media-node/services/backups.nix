{ config, lib, ... }:

let
  cfg = config.homeOps.backups;
  nas = config.homeOps.nas;
in
{
  options.homeOps.backups = {
    enable = lib.mkEnableOption "nightly restic backup of service state to the NAS";
    repository = lib.mkOption {
      type = lib.types.str;
      default = "${nas.mountPoint}/backups/media-node";
      description = "restic repository path (on the NAS mount).";
    };
    passwordFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.homeOps.secrets.directory}/restic-password";
      description = "Repository encryption key. Generated on first boot; copy it off-box or the backups are unreadable after a rebuild.";
    };
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "02:30";
      description = "systemd OnCalendar for the nightly run.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = nas.enable;
        message = "homeOps.backups requires homeOps.nas.enable: the repository lives on the NAS.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.backups requires homeOps.secrets.enable for the repository key.";
      }
    ];

    # Merges into the generated-secrets list; the *api-key/other rule makes it hex48.
    homeOps.secrets.files = [ "restic-password" ];

    # Everything under /var/lib that cannot be regenerated from this repo:
    # runtime secrets, every Arr/Jellyfin/Authelia/EPlusTV database, VPN state.
    # Total is ~2G, so no need to be clever about excludes.
    services.restic.backups.media-node = {
      initialize = true;
      repository = cfg.repository;
      passwordFile = cfg.passwordFile;
      paths = [ "/var/lib" ];
      exclude = [
        "/var/lib/docker"
        "/var/lib/systemd"
        "/var/lib/jellyfin/temp"
        "/var/lib/jellyfin/log"
        "*.log"
      ];
      extraBackupArgs = [ "--exclude-caches" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
      pruneOpts = [
        "--keep-daily 30"
        "--keep-weekly 8"
      ];
    };

    systemd.services.restic-backups-media-node.unitConfig.RequiresMountsFor = [ nas.mountPoint ];
  };
}
