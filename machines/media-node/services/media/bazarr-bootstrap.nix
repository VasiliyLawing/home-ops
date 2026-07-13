{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.bazarrBootstrap;
  bootstrapBazarr = pkgs.buildGoModule {
    pname = "home-ops-bootstrap-bazarr";
    version = "0.1.0";
    src = ../../scripts/runtime-secrets/bazarr-bootstrap;
    vendorHash = null;
    env.CGO_ENABLED = "0";
  };
in
{
  options.homeOps.media.bazarrBootstrap = {
    enable = lib.mkEnableOption "Bazarr Sonarr/Radarr settings bootstrap";
    configFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/bazarr/config/config.yaml";
      description = "Bazarr config.yaml path.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.moviesTv.enable;
        message = "homeOps.media.bazarrBootstrap requires homeOps.media.moviesTv.enable.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.bazarrBootstrap requires homeOps.secrets.enable.";
      }
    ];

    # The upstream bazarr module already creates the static bazarr user/group
    # and runs without DynamicUser; only the config dir needs to exist early.
    systemd.tmpfiles.rules = [
      "d /var/lib/bazarr 0750 bazarr bazarr -"
      "d /var/lib/bazarr/config 0750 bazarr bazarr -"
    ];

    systemd.services.home-ops-bazarr-bootstrap = {
      description = "Bootstrap Bazarr Sonarr/Radarr settings";
      wantedBy = [ "multi-user.target" ];
      after = [
        "home-ops-runtime-secrets.service"
        "home-ops-arr-configs.service"
      ];
      requires = [
        "home-ops-runtime-secrets.service"
        "home-ops-arr-configs.service"
      ];
      before = [ "bazarr.service" ];
      environment = {
        HOME_OPS_BAZARR_CONFIG_FILE = cfg.configFile;
        HOME_OPS_SONARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/sonarr-api-key";
        HOME_OPS_RADARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/radarr-api-key";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${bootstrapBazarr}/bin/home-ops-bootstrap-bazarr";
        ExecStartPost = "${pkgs.coreutils}/bin/chown bazarr:bazarr ${cfg.configFile}";
        RemainAfterExit = true;
      };
    };

    systemd.services.bazarr = {
      requires = [ "home-ops-bazarr-bootstrap.service" ];
      after = [ "home-ops-bazarr-bootstrap.service" ];
    };
  };
}
