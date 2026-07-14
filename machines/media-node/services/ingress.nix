{ config, lib, ... }:

let
  cfg = config.homeOps.ingress;
  autheliaCfg = config.homeOps.authelia;
  dashboardCfg = config.homeOps.dashboard;
  wizarrCfg = config.homeOps.media.wizarr;
  forwardAuthBlock = ''
    forward_auth 127.0.0.1:${toString autheliaCfg.port} {
      uri /api/authz/forward-auth
      copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
    }
  '';
  autheliaProtects = host: autheliaCfg.enable && (lib.elem host autheliaCfg.protectedHosts);
  # Homepage: browser-only, no native clients — safe to gate the whole thing.
  dashboardRouteBlock =
    (lib.optionalString (autheliaProtects dashboardCfg.host) forwardAuthBlock)
    + ''
      reverse_proxy 127.0.0.1:${toString dashboardCfg.port}
    '';
in
{
  options.homeOps.ingress = {
    enable = lib.mkEnableOption "Caddy reverse proxy routes";
    jellyfinHost = lib.mkOption {
      type = lib.types.str;
      default = "media.example.com";
    };
  };

  config = lib.mkIf cfg.enable {
    # Router forwards public 80 -> internal 1919, public 443 -> internal 2929;
    # Caddy binds those and ACME HTTP-01 still works because LE hits :80 externally.
    networking.firewall.allowedTCPPorts = [
      1919
      2929
    ];

    services.caddy = {
      enable = true;
      globalConfig = ''
        http_port 1919
        https_port 2929
      '';
      virtualHosts = lib.mkMerge [
        {
          ${cfg.jellyfinHost}.extraConfig = ''
            reverse_proxy 127.0.0.1:8096
          '';
        }
        (lib.mkIf autheliaCfg.enable {
          ${autheliaCfg.host}.extraConfig = ''
            reverse_proxy 127.0.0.1:${toString autheliaCfg.port}
          '';
        })
        (lib.mkIf dashboardCfg.enable {
          ${dashboardCfg.host}.extraConfig = dashboardRouteBlock;
        })
        # Wizarr must be publicly reachable without auth: invitees click a link
        # in an email/message and land here to claim their Jellyfin account.
        # Putting Authelia in front defeats the point.
        (lib.mkIf wizarrCfg.enable {
          "invite.lawing.net".extraConfig = ''
            reverse_proxy 127.0.0.1:${toString wizarrCfg.port}
          '';
        })
      ];
    };
  };
}
