{ config, lib, pkgs, ... }:

let
  cfg = config.homeOps.media.moviesTv;
  secrets = config.homeOps.secrets;
  recyclarrConfig = pkgs.writeText "recyclarr.yml" ''
    sonarr:
      media-node:
        base_url: http://127.0.0.1:8989
        api_key: !env_var SONARR_API_KEY
    radarr:
      media-node:
        base_url: http://127.0.0.1:7878
        api_key: !env_var RADARR_API_KEY
  '';
  recyclarrRun = pkgs.writeShellScript "recyclarr-sync" ''
    set -eu
    read_api_key() {
      app="$1"
      shift
      for file in "$@"; do
        if [ -r "$file" ]; then
          api_key="$(${pkgs.gnused}/bin/sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$file" | ${pkgs.coreutils}/bin/head -n1)"
          if [ -n "$api_key" ]; then
            printf '%s\n' "$api_key"
            return 0
          fi
        fi
      done
      echo "Unable to find $app API key" >&2
      return 1
    }

    export SONARR_API_KEY="$(read_api_key sonarr /var/lib/sonarr/config.xml /var/lib/sonarr/.config/NzbDrone/config.xml)"
    export RADARR_API_KEY="$(read_api_key radarr /var/lib/radarr/config.xml /var/lib/radarr/.config/Radarr/config.xml)"
    exec ${pkgs.recyclarr}/bin/recyclarr sync --config ${recyclarrConfig}
  '';
in
{
  options.homeOps.media.moviesTv = {
    enable = lib.mkEnableOption "movies and TV automation";
    flaresolverr.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Flaresolverr for indexers that need challenge solving.";
    };
    recyclarr.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    neutarr.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.recyclarr.enable || secrets.enable;
        message = "homeOps.media.moviesTv.recyclarr requires homeOps.secrets.enable.";
      }
    ];

    services.sonarr = {
      enable = true;
      group = "media";
      openFirewall = false;
    };
    services.radarr = {
      enable = true;
      group = "media";
      openFirewall = false;
    };
    services.prowlarr = {
      enable = true;
      openFirewall = false;
    };
    services.bazarr = {
      enable = true;
      openFirewall = false;
    };
    services.flaresolverr = lib.mkIf cfg.flaresolverr.enable {
      enable = true;
      openFirewall = false;
    };

    systemd.services.recyclarr-sync = lib.mkIf cfg.recyclarr.enable {
      description = "Sync Recyclarr quality/profile config";
      after = [
        "sonarr.service"
        "radarr.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = recyclarrRun;
      };
    };

    systemd.timers.recyclarr-sync = lib.mkIf cfg.recyclarr.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    virtualisation.oci-containers.containers.neutarr = lib.mkIf cfg.neutarr.enable {
      image = "ghcr.io/gh-code-forge/neutarr:latest";
      autoStart = true;
      volumes = [ "/var/lib/home-ops/neutarr:/config" ];
      extraOptions = [ "--pull=newer" ];
    };
  };
}
