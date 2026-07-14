{ config, lib, ... }:

let
  cfg = config.homeOps.ingress;
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
      virtualHosts = {
        ${cfg.jellyfinHost}.extraConfig = ''
          reverse_proxy 127.0.0.1:8096
        '';
        ${cfg.requestsHost}.extraConfig = ''
          reverse_proxy 127.0.0.1:5055
        '';
      };
    };
  };
}
