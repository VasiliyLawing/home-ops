{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.jellyfinBootstrap;
  bootstrapJellyfin = pkgs.buildGoModule {
    pname = "home-ops-bootstrap-jellyfin";
    version = "0.1.0";
    src = ../../scripts/runtime-secrets/jellyfin-bootstrap;
    vendorHash = null;
    env.CGO_ENABLED = "0";
    postInstall = ''
      if [ -x "$out/bin/jellyfin-bootstrap" ]; then
        mv "$out/bin/jellyfin-bootstrap" "$out/bin/home-ops-bootstrap-jellyfin"
      elif [ -x "$out/bin/home-ops-jellyfin-bootstrap" ]; then
        mv "$out/bin/home-ops-jellyfin-bootstrap" "$out/bin/home-ops-bootstrap-jellyfin"
      else
        echo "Could not find Jellyfin bootstrap binary. Available binaries:" >&2
        ls -la "$out/bin" >&2
        exit 1
      fi
    '';
  };
in
{
  options.homeOps.media.jellyfinBootstrap = {
    enable = lib.mkEnableOption "Jellyfin library bootstrap";
    apiKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.homeOps.secrets.directory}/jellyfin-api-key";
      description = "Host-local Jellyfin API key created after Jellyfin admin setup.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.shared.enable;
        message = "homeOps.media.jellyfinBootstrap requires homeOps.media.shared.enable.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.jellyfinBootstrap requires homeOps.secrets.enable.";
      }
    ];

    systemd.services.home-ops-jellyfin-bootstrap = {
      description = "Bootstrap Jellyfin media libraries";
      after = [
        "jellyfin.service"
      ];
      wants = [
        "jellyfin.service"
      ];
      unitConfig.RequiresMountsFor = [ config.homeOps.media.shared.dataRoot ];
      environment = {
        HOME_OPS_JELLYFIN_API_KEY_FILE = cfg.apiKeyFile;
        HOME_OPS_JELLYFIN_BASE_URL = "http://127.0.0.1:8096";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${bootstrapJellyfin}/bin/home-ops-bootstrap-jellyfin";
        RemainAfterExit = true;
      };
    };
  };
}
