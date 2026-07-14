{ config, lib, pkgs, ... }:

let
  cfg = config.homeOps.media.shared;
in
{
  options.homeOps.media.shared = {
    enable = lib.mkEnableOption "shared media directories and core services";
    dataRoot = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nas/data";
      description = "NAS-backed media and download mount point.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.nas.enable;
        message = "homeOps.media.shared requires homeOps.nas.enable so media paths live on the NAS.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/home-ops/aurral 0775 homeops media -"
      "d /var/lib/home-ops/calibre-web-automated 0775 homeops media -"
      "d /var/lib/home-ops/neutarr 0775 homeops media -"
      "d /var/lib/home-ops/shelfmark 0775 homeops media -"
      "L+ /data - - - - ${cfg.dataRoot}"
      "d ${cfg.dataRoot}/torrents 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/complete 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/complete/movies 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/complete/tv 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/complete/music 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/complete/books 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/complete/audiobooks 0775 homeops media -"
      "d ${cfg.dataRoot}/torrents/incomplete 0775 homeops media -"
      "d ${cfg.dataRoot}/media 0775 homeops media -"
      "d ${cfg.dataRoot}/media/movies 0775 homeops media -"
      "d ${cfg.dataRoot}/media/tv 0775 homeops media -"
      "d ${cfg.dataRoot}/media/music 0775 homeops media -"
      "d ${cfg.dataRoot}/media/music/aurral 0775 homeops media -"
      "d ${cfg.dataRoot}/media/podcasts 0775 homeops media -"
      "d ${cfg.dataRoot}/media/books 0775 homeops media -"
      "d ${cfg.dataRoot}/media/books/imports 0775 homeops media -"
      "d ${cfg.dataRoot}/media/books/library 0775 homeops media -"
      "d ${cfg.dataRoot}/media/audiobooks 0775 homeops media -"
      "d ${cfg.dataRoot}/media/audiobooks/imports 0775 homeops media -"
    ];

    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker.enable = true;

    services.jellyfin = {
      enable = true;
      openFirewall = true;
      group = "media";
    };

    # Jellyfin's network.xml is app-managed (not a NixOS option), so we patch
    # it before start if KnownProxies is still empty. Trusting 127.0.0.1 lets
    # Jellyfin honor Caddy's X-Forwarded-Proto and generate https URLs (the
    # SSO plugin depends on this to build its OIDC redirect_uri).
    systemd.services.jellyfin.preStart = ''
      cfg=/var/lib/jellyfin/config/network.xml
      if [ -f "$cfg" ] && grep -q '<KnownProxies />' "$cfg"; then
        ${pkgs.gnused}/bin/sed -i \
          's|<KnownProxies />|<KnownProxies>\n    <string>127.0.0.1</string>\n  </KnownProxies>|' \
          "$cfg"
      fi
    '';

    # GPU access for VAAPI transcoding and Vulkan tone mapping on the 780M.
    users.users.jellyfin.extraGroups = [
      "render"
      "video"
    ];

    services.seerr = {
      enable = true;
      openFirewall = true;
    };

    users = {
      groups.seerr = { };
      users.seerr = {
        description = "Seerr service user";
        isSystemUser = true;
        group = "seerr";
      };
    };

    systemd.services.jellyfin.unitConfig.RequiresMountsFor = [ cfg.dataRoot ];
    systemd.services.seerr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "seerr";
      Group = "seerr";
      StateDirectory = lib.mkForce "seerr";
    };

    system.activationScripts.homeOpsSeerrStateDir = {
      deps = [ "users" ];
      text = ''
      if [ -L /var/lib/seerr ]; then
        target="$(readlink -f /var/lib/seerr || true)"
        rm -f /var/lib/seerr
        if [ -n "$target" ] && [ -d "$target" ]; then
          mv "$target" /var/lib/seerr
        else
          install -d -m 0750 -o seerr -g seerr /var/lib/seerr
        fi
      else
        install -d -m 0750 -o seerr -g seerr /var/lib/seerr
      fi
      chown -R seerr:seerr /var/lib/seerr
      '';
    };
  };
}
