{ config, lib, ... }:

let
  cfg = config.homeOps.media.eplustv;
in
{
  options.homeOps.media.eplustv = {
    enable = lib.mkEnableOption "EPlusTV — turns your own NFL+/Sunday Ticket/ESPN/etc. subscriptions into M3U + XMLTV linear channels";
    image = lib.mkOption {
      type = lib.types.str;
      default = "m0ngr31/eplustv:v4.16.3";
      description = "Pinned EPlusTV image. Provider logins break often; keep this current.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/eplustv";
      description = "EPlusTV DB and provider session state.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0775 homeops media -"
    ];

    virtualisation.oci-containers.containers.eplustv = {
      image = cfg.image;
      autoStart = true;
      volumes = [ "${cfg.dataDir}:/app/config" ];
      environment = {
        TZ = config.time.timeZone;
        PUID = "1000";
        PGID = "1001";
      };
      # Deliberately NOT in the Gluetun island: these are the operator's own
      # paid accounts, and logging into NFL/ESPN from a foreign VPN exit is
      # how they get geo-blocked or flagged. Host networking on port 8000,
      # Tailscale-only via trustedInterfaces=tailscale0. Dispatcharr consumes
      # http://127.0.0.1:8000/channels.m3u and /xmltv.xml.
      extraOptions = [ "--network=host" ];
    };
  };
}
