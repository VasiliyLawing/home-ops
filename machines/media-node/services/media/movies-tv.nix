{ config, lib, ... }:

let
  cfg = config.homeOps.media.moviesTv;
in
{
  options.homeOps.media.moviesTv = {
    enable = lib.mkEnableOption "movies and TV automation";
    flaresolverr.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Flaresolverr for indexers that need challenge solving.";
    };
    neutarr.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable NeutArr, an automated missing-media hunter and quality-upgrader
        for the Arr apps.
      '';
    };
    neutarr.image = lib.mkOption {
      type = lib.types.str;
      default = "iampuid0/neutarr:1.8.0";
      description = "Pinned NeutArr container image.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.sonarr = {
      enable = true;
      group = "media";
      openFirewall = false;
    };
    services.radarr = {
      enable = true;
      group = "media";
      openFirewall = false;
    };
    services.prowlarr = {
      enable = true;
      openFirewall = false;
    };
    users = {
      groups.prowlarr = { };
      users.prowlarr = {
        description = "Prowlarr service user";
        isSystemUser = true;
        group = "prowlarr";
      };
    };
    # Prowlarr's generated config.xml is seeded before the service starts, so it
    # needs a stable owner. The upstream service uses DynamicUser; force a static
    # system user here so the config file can remain least-privilege owned by
    # prowlarr:prowlarr instead of falling back to root-owned readable config.
    systemd.services.prowlarr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "prowlarr";
      Group = "prowlarr";
    };
    services.bazarr = {
      enable = true;
      openFirewall = false;
    };
    services.flaresolverr = lib.mkIf cfg.flaresolverr.enable {
      enable = true;
      openFirewall = false;
    };

    virtualisation.oci-containers.containers.neutarr = lib.mkIf cfg.neutarr.enable {
      image = cfg.neutarr.image;
      autoStart = true;
      environment = {
        PUID = "1000";
        PGID = "1001";
        TZ = config.time.timeZone;
      };
      volumes = [ "/var/lib/home-ops/neutarr:/config" ];
      # Host networking → --add-host isn't meaningful; host.docker.internal
      # is superseded by plain 127.0.0.1 pointing at the actual host.
      extraOptions = [ "--network=host" ];
    };
  };
}
