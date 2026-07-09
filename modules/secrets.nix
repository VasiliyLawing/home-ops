{ config, lib, pkgs, ... }:

let
  cfg = config.homeOps.secrets;
  generateSecrets = pkgs.writeShellScript "home-ops-generate-runtime-secrets" ''
    set -eu
    install -d -m 0700 -o root -g root ${cfg.directory}
    for name in ${lib.concatStringsSep " " cfg.files}; do
      path="${cfg.directory}/$name"
      if [ ! -e "$path" ]; then
        ${pkgs.openssl}/bin/openssl rand -base64 48 > "$path"
        chmod 0600 "$path"
        chown root:root "$path"
      fi
    done
  '';
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
        "recyclarr-api-key"
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
        "qbittorrent.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = generateSecrets;
        RemainAfterExit = true;
      };
    };
  };
}
