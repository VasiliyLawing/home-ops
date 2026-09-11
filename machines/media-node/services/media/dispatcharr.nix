{ config, lib, ... }:

let
  cfg = config.homeOps.media.dispatcharr;
in
{
  options.homeOps.media.dispatcharr = {
    enable = lib.mkEnableOption "Dispatcharr — IPTV playlist/EPG manager and HDHomeRun emulator for Jellyfin Live TV";
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/dispatcharr/dispatcharr:0.30.0";
      description = "Pinned Dispatcharr all-in-one image (bundles Postgres + Redis + Celery).";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/dispatcharr";
      description = "Dispatcharr state: Postgres cluster, cached playlists/EPG, config.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.dispatcharr = {
      image = cfg.image;
      autoStart = true;
      volumes = [ "${cfg.dataDir}:/data" ];
      environment = {
        TZ = config.time.timeZone;
        DISPATCHARR_ENV = "aio";
        DISPATCHARR_LOG_LEVEL = "info";
        # aio mode: Postgres over its unix socket, Redis on loopback.
        REDIS_HOST = "localhost";
        CELERY_BROKER_URL = "redis://localhost:6379/0";
      };
      # Host networking so Jellyfin sees the HDHomeRun emulation on the LAN
      # discovery port and consumers (Jellyfin, Sportarr) hit it at
      # 127.0.0.1:9191. Side effect: the bundled Redis binds host loopback
      # 6379 — nothing else on this box uses it. UI is Tailscale-only via
      # trustedInterfaces=tailscale0; LAN blocked by the firewall.
      extraOptions = [ "--network=host" ];
    };
  };
}
