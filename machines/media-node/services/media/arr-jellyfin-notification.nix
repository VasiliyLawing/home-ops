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
  # The secrets dir is root-only; the arrs run as radarr/sonarr (group media).
  arrKeyFile = "/var/lib/home-ops/arr-jellyfin-api-key";
  # Run by Sonarr/Radarr as a Custom Script connection on import/upgrade/rename.
  notifyScript = pkgs.writeShellApplication {
    name = "home-ops-arr-jellyfin-notify";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      # Saving the connection in the arrs runs a "Test" event; nothing to scan.
      [ "''${radarr_eventtype:-''${sonarr_eventtype:-}}" = "Test" ] && exit 0
      path="''${radarr_movie_path:-''${sonarr_series_path:-}}"
      [ -n "$path" ] || exit 0
      key="$(cat ${arrKeyFile})"
      jq -n --arg p "$path" '{Updates: [{Path: $p, UpdateType: "Modified"}]}' \
        | curl -fsS -X POST \
          -H "Authorization: MediaBrowser Client=\"home-ops\", Device=\"arr\", DeviceId=\"home-ops-arr\", Version=\"1.0\", Token=\"$key\"" \
          -H "Content-Type: application/json" --data @- \
          http://127.0.0.1:8096/Library/Media/Updated
    '';
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
        HOME_OPS_JELLYFIN_NOTIFY_SCRIPT = "${notifyScript}/bin/home-ops-arr-jellyfin-notify";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/install -m 0440 -o root -g media ${config.homeOps.media.jellyfinBootstrap.apiKeyFile} ${arrKeyFile}";
        ExecStart = "${bootstrapArrJellyfinNotification}/bin/home-ops-bootstrap-arr-jellyfin-notification";
        RemainAfterExit = true;
      };
    };
  };
}
