{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.seerrBootstrap;
  bootstrapSeerr = pkgs.buildGoModule {
    pname = "home-ops-bootstrap-seerr";
    version = "0.1.0";
    src = ../../scripts/runtime-secrets/seerr-bootstrap;
    vendorHash = null;
    env.CGO_ENABLED = "0";
    postInstall = ''
      if [ -x "$out/bin/seerr-bootstrap" ]; then
        mv "$out/bin/seerr-bootstrap" "$out/bin/home-ops-bootstrap-seerr"
      elif [ -x "$out/bin/home-ops-seerr-bootstrap" ]; then
        mv "$out/bin/home-ops-seerr-bootstrap" "$out/bin/home-ops-bootstrap-seerr"
      else
        echo "Could not find Seerr bootstrap binary. Available binaries:" >&2
        ls -la "$out/bin" >&2
        exit 1
      fi
    '';
  };
in
{
  options.homeOps.media.seerrBootstrap = {
    enable = lib.mkEnableOption "Seerr Jellyfin/Sonarr/Radarr settings bootstrap";
    settingsFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/seerr/settings.json";
      description = "Seerr settings.json path.";
    };
    jellyfinApiKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.homeOps.secrets.directory}/jellyfin-api-key";
      description = "Optional host-local Jellyfin API key. Create this manually after Jellyfin admin setup.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.shared.enable;
        message = "homeOps.media.seerrBootstrap requires homeOps.media.shared.enable.";
      }
      {
        assertion = config.homeOps.media.moviesTv.enable;
        message = "homeOps.media.seerrBootstrap requires homeOps.media.moviesTv.enable.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.seerrBootstrap requires homeOps.secrets.enable.";
      }
    ];

    systemd.services.home-ops-seerr-bootstrap = {
      description = "Bootstrap Seerr Jellyfin/Sonarr/Radarr settings";
      after = [
        "home-ops-runtime-secrets.service"
        "home-ops-arr-configs.service"
        "jellyfin.service"
        "sonarr.service"
        "radarr.service"
        "seerr.service"
      ];
      wants = [
        "jellyfin.service"
        "sonarr.service"
        "radarr.service"
        "seerr.service"
      ];
      requires = [
        "home-ops-runtime-secrets.service"
        "home-ops-arr-configs.service"
      ];
      environment = {
        HOME_OPS_SEERR_SETTINGS_FILE = cfg.settingsFile;
        HOME_OPS_JELLYFIN_API_KEY_FILE = cfg.jellyfinApiKeyFile;
        HOME_OPS_SONARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/sonarr-api-key";
        HOME_OPS_RADARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/radarr-api-key";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${bootstrapSeerr}/bin/home-ops-bootstrap-seerr";
        ExecStartPost = [
          "${pkgs.runtimeShell} -c '${pkgs.coreutils}/bin/chown seerr:seerr ${cfg.settingsFile} || true'"
          "${pkgs.systemd}/bin/systemctl try-restart seerr.service"
        ];
        RemainAfterExit = true;
      };
    };
  };
}
