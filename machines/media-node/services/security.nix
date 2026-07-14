{ config, lib, ... }:

let
  cfg = config.homeOps.security;
in
{
  options.homeOps.security = {
    enable = lib.mkEnableOption "fail2ban baseline hardening for public-facing services";
  };

  config = lib.mkIf cfg.enable {
    # Jellyfin filter matches its "Authentication request for ... has been denied
    # (IP: ...)" log line. Sample:
    #   [2026-07-13 23:32:02.786 -05:00] [INF] [3] ...UserManager: Authentication
    #   request for "lawing" has been denied (IP: "192.168.1.250").
    environment.etc."fail2ban/filter.d/jellyfin.conf".text = ''
      [Definition]
      failregex = ^.*Authentication request for ".*" has been denied \(IP: "<HOST>"\)
      ignoreregex =
    '';

    services.fail2ban = {
      enable = true;
      # Cross-jail counting so an attacker banned on Jellyfin doesn't just move to
      # another service; the ban list is shared.
      bantime-increment = {
        enable = true;
        overalljails = true;
      };
      # Never ban our own LAN or the Tailscale range.
      ignoreIP = [
        "127.0.0.1/8"
        "192.168.1.0/24"
        "100.64.0.0/10"
      ];
      jails.jellyfin.settings = {
        enabled = true;
        filter = "jellyfin";
        logpath = "/var/lib/jellyfin/log/log_*.log";
        # 5 failures within 10 min → 1 hour ban; bantime-increment escalates
        # repeat offenders automatically.
        maxretry = 5;
        findtime = 600;
        bantime = 3600;
      };
    };
  };
}
