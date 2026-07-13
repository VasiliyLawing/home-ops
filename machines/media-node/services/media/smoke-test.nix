{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.smokeTest;
  smokeTest = pkgs.buildGoModule {
    pname = "home-ops-smoke-test";
    version = "0.1.0";
    src = ../../scripts/runtime-secrets/smoke-test;
    vendorHash = null;
    env.CGO_ENABLED = "0";
    postInstall = ''
      if [ -x "$out/bin/smoke-test" ]; then
        mv "$out/bin/smoke-test" "$out/bin/home-ops-smoke-test"
      elif [ -x "$out/bin/home-ops-smoke-test" ]; then
        true
      else
        echo "Could not find smoke-test binary. Available binaries:" >&2
        ls -la "$out/bin" >&2
        exit 1
      fi
    '';
  };
in
{
  options.homeOps.media.smokeTest = {
    enable = lib.mkEnableOption "on-demand Home Ops smoke test";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.shared.enable;
        message = "homeOps.media.smokeTest requires homeOps.media.shared.enable.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.smokeTest requires homeOps.secrets.enable.";
      }
    ];

    systemd.services.home-ops-smoke-test = {
      description = "Run Home Ops media-node smoke checks";
      after = [
        "network-online.target"
        "home-ops-runtime-secrets.service"
        "jellyfin.service"
        "seerr.service"
        "sonarr.service"
        "radarr.service"
        "prowlarr.service"
        "bazarr.service"
        "docker-gluetun.service"
        "docker-qbittorrent.service"
      ];
      wants = [
        "network-online.target"
        "home-ops-runtime-secrets.service"
        "jellyfin.service"
        "seerr.service"
        "sonarr.service"
        "radarr.service"
        "prowlarr.service"
        "bazarr.service"
        "docker-gluetun.service"
        "docker-qbittorrent.service"
      ];
      unitConfig.RequiresMountsFor = [ config.homeOps.media.shared.dataRoot ];
      path = [
        pkgs.coreutils
        pkgs.docker
        pkgs.systemd
      ];
      environment = {
        HOME_OPS_DATA_ROOT = config.homeOps.media.shared.dataRoot;
        HOME_OPS_SECRET_DIRECTORY = config.homeOps.secrets.directory;
        HOME_OPS_SEERR_SETTINGS_FILE = config.homeOps.media.seerrBootstrap.settingsFile;
        HOME_OPS_QBIT_SAVE_PATH = config.homeOps.media.downloads.qbittorrent.savePath;
        HOME_OPS_QBIT_TEMP_PATH = config.homeOps.media.downloads.qbittorrent.incompletePath;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${smokeTest}/bin/home-ops-smoke-test";
      };
    };
  };
}
