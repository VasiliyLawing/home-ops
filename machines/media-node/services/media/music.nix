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
      image = "ghcr.io/aurral-app/aurral:latest";
      autoStart = true;
      ports = [ "127.0.0.1:8098:3000" ];
      volumes = [
        "/var/lib/home-ops/aurral:/config"
        "${shared.dataRoot}/torrents/complete:/downloads"
        "${shared.dataRoot}/media/music:/music"
        "${shared.dataRoot}/media/podcasts:/podcasts"
      ];
      extraOptions = [ "--pull=always" ];
    };
  };
}
