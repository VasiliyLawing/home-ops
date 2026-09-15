{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.eplustv;
in
{
  options.homeOps.media.eplustv = {
    enable = lib.mkEnableOption "EPlusTV — turns your own NFL+/Sunday Ticket/ESPN/etc. subscriptions into M3U + XMLTV linear channels";
    image = lib.mkOption {
      type = lib.types.str;
      default = "m0ngr31/eplustv:v4.16.5";
      description = "Pinned EPlusTV image. Provider logins break often; keep this current.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/eplustv";
      description = "EPlusTV DB and provider session state.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 0700: the DB files hold NFL/Google session tokens. The container writes
    # them 0644, so the directory is what keeps other service users out.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 homeops media -"
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
      # Tailscale-only via trustedInterfaces=tailscale0. Jellyfin (M3U tuner
      # + XMLTV) and Sportarr (IPTV + EPG source) consume
      # http://127.0.0.1:8000/{channels,linear-channels}.m3u and
      # /{xmltv,linear-xmltv}.xml directly.
      extraOptions = [ "--network=host" ];
    };

    # EPlusTV keeps a provider stream session per channel and re-uses it after
    # NFL's CDN has expired it (410 -> the channel 404s until a restart). A
    # nightly restart is the crude fix; logins persist in dataDir.
    systemd.services.eplustv-restart = {
      description = "Restart EPlusTV to drop stale provider stream sessions";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl restart docker-eplustv.service";
      };
    };
    systemd.timers.eplustv-restart = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "04:00";
    };
  };
}
