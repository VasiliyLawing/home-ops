{ config, lib, ... }:

let
  cfg = config.homeOps.media.music;
  shared = config.homeOps.media.shared;
in
{
  options.homeOps.media.music = {
    enable = lib.mkEnableOption "music and podcast services";
    aurral.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable Aurral, a music discovery and request app for Lidarr.
      '';
    };
    aurral.image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/lklynet/aurral:1.76.0";
      description = "Pinned Aurral container image.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.lidarr = {
      enable = true;
      group = "media";
      openFirewall = false;
    };

    services.navidrome = {
      enable = true;
      settings = {
        Address = "127.0.0.1";
        Port = 4533;
        MusicFolder = "${shared.dataRoot}/media/music";
      };
    };

    systemd.services = {
      lidarr.unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      navidrome.unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      docker-aurral = lib.mkIf cfg.aurral.enable {
        unitConfig.RequiresMountsFor = [ shared.dataRoot ];
      };
    };

    virtualisation.oci-containers.containers.aurral = lib.mkIf cfg.aurral.enable {
      image = cfg.aurral.image;
      autoStart = true;
      ports = [ "127.0.0.1:8098:3001" ];
      environment = {
        PUID = "1000";
        PGID = "1001";
        TZ = config.time.timeZone;
        DOWNLOAD_FOLDER = "/app/downloads";
      };
      volumes = [
        "/var/lib/home-ops/aurral:/app/backend/data"
        "${shared.dataRoot}/media/music/aurral:/app/downloads"
        "${shared.dataRoot}/media/music:/data:ro"
      ];
      extraOptions = [ "--add-host=host.docker.internal:host-gateway" ];
    };
  };
}
