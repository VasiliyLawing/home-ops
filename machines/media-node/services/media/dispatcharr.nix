{ config, lib, ... }:

let
  cfg = config.homeOps.media.dispatcharr;
  downloads = config.homeOps.media.downloads;
  gluetunEnabled = downloads.gluetun.enable || downloads.qbittorrent.enable;
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
    port = lib.mkOption {
      type = lib.types.int;
      default = 9191;
      description = "Port Caddy serves Dispatcharr on (Tailscale-reachable; LAN blocked by the firewall). Consumers on the host use 127.0.0.1:<port>.";
    };
    internalPort = lib.mkOption {
      type = lib.types.int;
      default = 9190;
      description = "Port Dispatcharr listens on inside Gluetun's namespace, published to host loopback only.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = gluetunEnabled;
        message = "homeOps.media.dispatcharr requires Gluetun so IPTV traffic cannot leave outside the VPN.";
      }
      {
        assertion = config.homeOps.ingress.enable;
        message = "homeOps.media.dispatcharr requires homeOps.ingress.enable: Caddy fronts the loopback-only published port for Tailscale access.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    # Same island as qBittorrent: Gluetun owns the namespace, so playlist
    # fetches, EPG pulls and every stream leave via the VPN, and the kill
    # switch cuts them off if the tunnel drops. Docker's port publish bypasses
    # the NixOS firewall, so Gluetun publishes to host loopback only.
    virtualisation.oci-containers.containers = {
      gluetun.ports = [
        "127.0.0.1:${toString cfg.internalPort}:${toString cfg.internalPort}/tcp"
      ];

      dispatcharr = {
        image = cfg.image;
        autoStart = true;
        dependsOn = [ "gluetun" ];
        volumes = [ "${cfg.dataDir}:/data" ];
        environment = {
          TZ = config.time.timeZone;
          DISPATCHARR_ENV = "aio";
          DISPATCHARR_LOG_LEVEL = "info";
          DISPATCHARR_PORT = toString cfg.internalPort;
          # aio mode: Postgres over its unix socket, Redis on loopback inside
          # the Gluetun namespace (qBittorrent doesn't use 6379).
          REDIS_HOST = "localhost";
          CELERY_BROKER_URL = "redis://localhost:6379/0";
        };
        # Like qBittorrent, a Gluetun restart strands this container's
        # networking; restart docker-dispatcharr afterwards.
        extraOptions = [ "--network=container:gluetun" ];
      };
    };

    # Caddy on all interfaces + firewall (port not opened, tailscale0 trusted)
    # = Tailscale-only UI at http://media-node:9191, and Jellyfin/Sportarr keep
    # a single address, 127.0.0.1:9191. HDHomeRun auto-discovery is gone with
    # host networking; Jellyfin adds the tuner by URL instead.
    services.caddy.virtualHosts.":${toString cfg.port}".extraConfig = ''
      reverse_proxy 127.0.0.1:${toString cfg.internalPort} {
        # MPEG-TS streams: never buffer.
        flush_interval -1
      }
    '';
  };
}
