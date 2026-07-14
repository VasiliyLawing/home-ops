{ config, lib, ... }:

let
  cfg = config.homeOps.media.wizarr;
in
{
  options.homeOps.media.wizarr = {
    enable = lib.mkEnableOption "Wizarr Jellyfin invitation service";
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/wizarrrr/wizarr:2026.7.1";
      description = "Pinned Wizarr container image.";
    };
    port = lib.mkOption {
      type = lib.types.int;
      default = 5690;
      description = "Host port bound to 127.0.0.1 only; Caddy fronts external access.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/wizarr";
      description = "Host path holding Wizarr's SQLite database and uploads.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.wizarr = {
      image = cfg.image;
      ports = [ "127.0.0.1:${toString cfg.port}:5690" ];
      volumes = [ "${cfg.dataDir}:/data/database" ];
      environment = {
        TZ = config.time.timeZone;
      };
    };
  };
}
