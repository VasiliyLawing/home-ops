{ config, lib, pkgs, ... }:

let
  cfg = config.homeOps.media.books;
in
{
  options.homeOps.media.books = {
    enable = lib.mkEnableOption "books and audiobooks services";
    shelfmark.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    services.audiobookshelf = {
      enable = true;
      host = "127.0.0.1";
      port = 13378;
    };

    services.calibre-web = {
      enable = true;
      listen.ip = "127.0.0.1";
      listen.port = 8083;
      group = "media";
      options = {
        calibreLibrary = "/data/media/books";
        enableBookUploading = true;
      };
    };

    environment.systemPackages = lib.mkIf cfg.shelfmark.enable [ pkgs.shelfmark ];

    virtualisation.oci-containers.containers.shelfmark = lib.mkIf cfg.shelfmark.enable {
      image = "ghcr.io/daniel-lxs/shelfmark:latest";
      autoStart = true;
      ports = [ "127.0.0.1:8099:8080" ];
      volumes = [
        "/var/lib/home-ops/shelfmark:/config"
        "/data/media/books:/books"
      ];
      extraOptions = [ "--pull=newer" ];
    };
  };
}
