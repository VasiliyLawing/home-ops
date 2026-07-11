{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.secrets;
  secretPath = name: "${cfg.directory}/${name}";
  arrConfigs = pkgs.writeText "home-ops-arr-configs" (
    lib.concatStringsSep "\n" (
      lib.optionals config.services.sonarr.enable [
        "sonarr|Sonarr|8989|${config.services.sonarr.dataDir}/config.xml|${secretPath "sonarr-api-key"}|sonarr|media"
      ]
      ++ lib.optionals config.services.radarr.enable [
        "radarr|Radarr|7878|${config.services.radarr.dataDir}/config.xml|${secretPath "radarr-api-key"}|radarr|media"
      ]
      ++ lib.optionals config.services.prowlarr.enable [
        "prowlarr|Prowlarr|9696|${config.services.prowlarr.dataDir}/config.xml|${secretPath "prowlarr-api-key"}|prowlarr|prowlarr"
      ]
      ++ lib.optionals config.services.lidarr.enable [
        "lidarr|Lidarr|8686|${config.services.lidarr.dataDir}/config.xml|${secretPath "lidarr-api-key"}|lidarr|media"
      ]
    )
    + "\n"
  );
  generateSecrets = pkgs.writeShellApplication {
    name = "home-ops-generate-runtime-secrets";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
    ];
    text = builtins.readFile ./scripts/runtime-secrets/generate-runtime-secrets.sh;
  };
  seedArrConfigs = pkgs.writeShellApplication {
    name = "home-ops-seed-arr-configs";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = builtins.readFile ./scripts/runtime-secrets/seed-arr-configs.sh;
  };
in
{
  options.homeOps.secrets = {
    enable = lib.mkEnableOption "host-local generated runtime secrets";
    directory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/home-ops/secrets";
      description = "Directory for runtime-generated secrets that should never enter the Nix store.";
    };
    files = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "sonarr-api-key"
        "radarr-api-key"
        "lidarr-api-key"
        "prowlarr-api-key"
        "qbittorrent-webui-username"
        "qbittorrent-webui-password"
      ];
      description = "Stable secret file names generated on first boot.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.home-ops-runtime-secrets = {
      description = "Generate host-local Home Ops runtime secrets";
      wantedBy = [ "multi-user.target" ];
      before = [
        "sonarr.service"
        "radarr.service"
        "lidarr.service"
        "prowlarr.service"
      ];
      environment = {
        HOME_OPS_SECRET_DIRECTORY = cfg.directory;
        HOME_OPS_SECRET_FILES = lib.concatStringsSep " " cfg.files;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${generateSecrets}/bin/home-ops-generate-runtime-secrets";
        RemainAfterExit = true;
      };
    };

    systemd.services.home-ops-arr-configs = {
      description = "Seed Arr application config files from Home Ops runtime secrets";
      wantedBy = [ "multi-user.target" ];
      after = [ "home-ops-runtime-secrets.service" ];
      requires = [ "home-ops-runtime-secrets.service" ];
      before = [
        "sonarr.service"
        "radarr.service"
        "lidarr.service"
        "prowlarr.service"
      ];
      environment.HOME_OPS_ARR_CONFIGS_FILE = arrConfigs;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${seedArrConfigs}/bin/home-ops-seed-arr-configs";
        RemainAfterExit = true;
      };
    };

    systemd.services.sonarr = lib.mkIf config.services.sonarr.enable {
      requires = [ "home-ops-arr-configs.service" ];
      after = [ "home-ops-arr-configs.service" ];
    };
    systemd.services.radarr = lib.mkIf config.services.radarr.enable {
      requires = [ "home-ops-arr-configs.service" ];
      after = [ "home-ops-arr-configs.service" ];
    };
    systemd.services.prowlarr = lib.mkIf config.services.prowlarr.enable {
      requires = [ "home-ops-arr-configs.service" ];
      after = [ "home-ops-arr-configs.service" ];
    };
    systemd.services.lidarr = lib.mkIf config.services.lidarr.enable {
      requires = [ "home-ops-arr-configs.service" ];
      after = [ "home-ops-arr-configs.service" ];
    };
  };
}
