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
    services.caddy = {
      enable = true;
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
