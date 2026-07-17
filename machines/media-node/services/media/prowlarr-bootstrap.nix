{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.prowlarrBootstrap;
  bootstrapProwlarr = pkgs.buildGoModule {
    pname = "home-ops-bootstrap-prowlarr";
    version = "0.1.0";
    src = ../../scripts/runtime-secrets/prowlarr-bootstrap;
    vendorHash = null;
    env.CGO_ENABLED = "0";
  };
in
{
  options.homeOps.media.prowlarrBootstrap = {
    enable = lib.mkEnableOption "Prowlarr app-link and indexer-proxy bootstrap";
    configFile = lib.mkOption {
      type = lib.types.path;
      default = ./config/prowlarr/bootstrap.json;
      description = "Non-secret Prowlarr bootstrap desired-state JSON.";
    };
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Systemd calendar expression for scheduled Prowlarr bootstrap syncs.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.moviesTv.enable;
        message = "homeOps.media.prowlarrBootstrap requires homeOps.media.moviesTv.enable.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.prowlarrBootstrap requires homeOps.secrets.enable.";
      }
    ];

    systemd.services.home-ops-prowlarr-bootstrap = {
      description = "Bootstrap Prowlarr app links and indexer proxies";
      after = [
        "home-ops-runtime-secrets.service"
        "home-ops-arr-configs.service"
        "prowlarr.service"
        "sonarr.service"
        "radarr.service"
      ]
      ++ lib.optionals config.services.flaresolverr.enable [
        "flaresolverr.service"
      ];
      wants = [
        "prowlarr.service"
        "sonarr.service"
        "radarr.service"
      ]
      ++ lib.optionals config.services.flaresolverr.enable [
        "flaresolverr.service"
      ];
      requires = [
        "home-ops-runtime-secrets.service"
        "home-ops-arr-configs.service"
      ];
      environment = {
        HOME_OPS_PROWLARR_BOOTSTRAP_CONFIG = "${cfg.configFile}";
        HOME_OPS_PROWLARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/prowlarr-api-key";
        HOME_OPS_SONARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/sonarr-api-key";
        HOME_OPS_RADARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/radarr-api-key";
        # Operator-provisioned (external account secret, like cloudflare-token):
        #   install -m 600 /dev/stdin /var/lib/home-ops/secrets/nzbgeek-api-key <<< "<key>"
        HOME_OPS_NZBGEEK_API_KEY_FILE = "${config.homeOps.secrets.directory}/nzbgeek-api-key";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${bootstrapProwlarr}/bin/home-ops-bootstrap-prowlarr";
        RemainAfterExit = true;
      };
    };

    systemd.timers.home-ops-prowlarr-bootstrap = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = false;
      };
    };
  };
}
