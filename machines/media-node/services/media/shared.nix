{ config, lib, ... }:

let
  cfg = config.homeOps.media.shared;
in
{
  options.homeOps.media.shared = {
    enable = lib.mkEnableOption "shared media directories and core services";
    dataRoot = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nas/data";
      description = "NAS-backed media and download mount point.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.nas.enable;
        message = "homeOps.media.shared requires homeOps.nas.enable so media paths live on the NAS.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/home-ops/aurral 0775 homeops media -"
      "d /var/lib/home-ops/neutarr 0775 homeops media -"
      "d /var/lib/home-ops/shelfmark 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/complete 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/complete/movies 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/complete/tv 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/complete/music 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/complete/books 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/incomplete 0775 homeops media -"
      "d ${cfg.dataRoot}/media 0775 homeops media -"
      "d ${cfg.dataRoot}/media/movies 0775 homeops media -"
      "d ${cfg.dataRoot}/media/tv 0775 homeops media -"
      "d ${cfg.dataRoot}/media/music 0775 homeops media -"
      "d ${cfg.dataRoot}/media/podcasts 0775 homeops media -"
      "d ${cfg.dataRoot}/media/books 0775 homeops media -"
      "d ${cfg.dataRoot}/media/books/imports 0775 homeops media -"
      "d ${cfg.dataRoot}/media/audiobooks 0775 homeops media -"
    ];

    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker.enable = true;

    services.jellyfin = {
      enable = true;
      openFirewall = true;
      group = "media";
    };

    services.seerr = {
      enable = true;
      openFirewall = false;
    };
  };
}
