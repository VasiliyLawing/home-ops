{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.arrJellyfinNotification;
  bootstrapArrJellyfinNotification = pkgs.buildGoModule {
    pname = "home-ops-bootstrap-arr-jellyfin-notification";
    version = "0.1.0";
    src = ../../scripts/runtime-secrets/arr-jellyfin-notification-bootstrap;
    vendorHash = null;
    env.CGO_ENABLED = "0";
  };
in
{
  options.homeOps.media.arrJellyfinNotification = {
    enable = lib.mkEnableOption "Sonarr/Radarr Jellyfin library-update notification bootstrap";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.moviesTv.enable;
        message = "homeOps.media.arrJellyfinNotification requires homeOps.media.moviesTv.enable.";
      }
      {
        assertion = config.homeOps.media.jellyfinBootstrap.enable;
        message = "homeOps.media.arrJellyfinNotification requires homeOps.media.jellyfinBootstrap.enable (for the Jellyfin API key).";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.arrJellyfinNotification requires homeOps.secrets.enable.";
      }
    ];

    # /mnt/nas is NFS, where Jellyfin's real-time file monitor never fires, so
    # freshly imported media only shows up on the scheduled library scan. This
    # wires Sonarr/Radarr to poke Jellyfin on import/upgrade/rename so new media
    # appears at once instead of waiting for the timer.
    systemd.services.home-ops-arr-jellyfin-notification = {
      description = "Bootstrap Sonarr/Radarr Jellyfin library-update notification";
      wantedBy = [ "multi-user.target" ];
      after = [
        "home-ops-runtime-secrets.service"
        "sonarr.service"
        "radarr.service"
        "jellyfin.service"
      ];
      wants = [
        "sonarr.service"
        "radarr.service"
        "jellyfin.service"
      ];
      requires = [ "home-ops-runtime-secrets.service" ];
      environment = {
        HOME_OPS_SONARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/sonarr-api-key";
        HOME_OPS_RADARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/radarr-api-key";
        HOME_OPS_JELLYFIN_API_KEY_FILE = config.homeOps.media.jellyfinBootstrap.apiKeyFile;
        HOME_OPS_JELLYFIN_HOST = "127.0.0.1";
        HOME_OPS_JELLYFIN_PORT = "8096";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${bootstrapArrJellyfinNotification}/bin/home-ops-bootstrap-arr-jellyfin-notification";
        RemainAfterExit = true;
      };
    };
  };
}
