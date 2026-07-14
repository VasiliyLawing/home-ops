{ config, lib, ... }:

let
  cfg = config.homeOps.ingress;
  autheliaCfg = config.homeOps.authelia;
  autheliaEnabled = autheliaCfg.enable && (lib.elem cfg.requestsHost autheliaCfg.protectedHosts);
  # Gate the browser SPA behind Authelia but leave /api/* unauthenticated so
  # native apps (Pocketseerr et al.) can still reach Seerr with their own
  # API keys — forward_auth would 302 them to the login page, which apps
  # can't follow. API brute-forcing is still gated by Seerr's own auth +
  # the fail2ban jail.
  seerrRouteBlock =
    if autheliaEnabled then
      ''
        handle /api/* {
          reverse_proxy 127.0.0.1:5055
        }
        handle {
          forward_auth 127.0.0.1:${toString autheliaCfg.port} {
            uri /api/authz/forward-auth
            copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
          }
          reverse_proxy 127.0.0.1:5055
        }
      ''
    else
      ''
        reverse_proxy 127.0.0.1:5055
      '';
in
{
  options.homeOps.ingress = {
    enable = lib.mkEnableOption "Caddy reverse proxy routes";
    jellyfinHost = lib.mkOption {
      type = lib.types.str;
      default = "media.example.com";
    };
    requestsHost = lib.mkOption {
      type = lib.types.str;
      default = "requests.example.com";
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
          ${cfg.requestsHost}.extraConfig = seerrRouteBlock;
        }
        (lib.mkIf autheliaCfg.enable {
          ${autheliaCfg.host}.extraConfig = ''
            reverse_proxy 127.0.0.1:${toString autheliaCfg.port}
          '';
        })
      ];
    };
  };
}
