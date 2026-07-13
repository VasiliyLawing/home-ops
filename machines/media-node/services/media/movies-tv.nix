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
      image = "ghcr.io/gh-code-forge/neutarr:latest";
      autoStart = true;
      volumes = [ "/var/lib/home-ops/neutarr:/config" ];
      extraOptions = [ "--pull=always" ];
    };
  };
}
