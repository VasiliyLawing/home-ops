{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.jellyfinPlugins;
  pluginState = pkgs.writeText "home-ops-jellyfin-plugins.json" (builtins.toJSON {
    repositories = cfg.repositories;
    packages = cfg.packages;
  });
  bootstrapPlugins = pkgs.buildGoModule {
    pname = "home-ops-bootstrap-jellyfin-plugins";
    version = "0.1.0";
    src = ../../scripts/runtime-secrets/jellyfin-plugin-bootstrap;
    vendorHash = null;
    env.CGO_ENABLED = "0";
  };
in
{
  options.homeOps.media.jellyfinPlugins = {
    enable = lib.mkEnableOption "Jellyfin plugin repository and install bootstrap";
    apiKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.homeOps.secrets.directory}/jellyfin-api-key";
      description = "Host-local Jellyfin API key created after Jellyfin admin setup.";
    };
    repositories = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          Name = lib.mkOption { type = lib.types.str; };
          Url = lib.mkOption { type = lib.types.str; };
          Enabled = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
        };
      });
      default = [
        {
          Name = "Intro Skipper";
          Url = "https://intro-skipper.org/manifest.json";
          Enabled = true;
        }
        {
          Name = "IAmParadox27";
          Url = "https://www.iamparadox.dev/jellyfin/plugins/manifest.json";
          Enabled = true;
        }
        {
          Name = "Jellyfin Enhanced";
          Url = "https://raw.githubusercontent.com/n00bcodr/jellyfin-plugins/main/10.11/manifest.json";
          Enabled = true;
        }
      ];
      description = "Jellyfin plugin repositories to merge into the server catalog.";
    };
    packages = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          repositoryUrl = lib.mkOption { type = lib.types.str; };
        };
      });
      default = [
        {
          name = "File Transformation";
          repositoryUrl = "https://www.iamparadox.dev/jellyfin/plugins/manifest.json";
        }
        {
          name = "Intro Skipper";
          repositoryUrl = "https://intro-skipper.org/manifest.json";
        }
        {
          name = "Media Bar";
          repositoryUrl = "https://www.iamparadox.dev/jellyfin/plugins/manifest.json";
        }
        {
          name = "Jellyfin Enhanced";
          repositoryUrl = "https://raw.githubusercontent.com/n00bcodr/jellyfin-plugins/main/10.11/manifest.json";
        }
      ];
      description = "Jellyfin plugin packages to install from the configured repositories.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.shared.enable;
        message = "homeOps.media.jellyfinPlugins requires homeOps.media.shared.enable.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.jellyfinPlugins requires homeOps.secrets.enable.";
      }
    ];

    systemd.services.home-ops-jellyfin-plugins = {
      description = "Bootstrap Jellyfin plugin repositories and desired plugins";
      after = [ "jellyfin.service" ];
      wants = [ "jellyfin.service" ];
      environment = {
        HOME_OPS_JELLYFIN_PLUGIN_CONFIG = "${pluginState}";
        HOME_OPS_JELLYFIN_API_KEY_FILE = cfg.apiKeyFile;
        HOME_OPS_JELLYFIN_BASE_URL = "http://127.0.0.1:8096";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${bootstrapPlugins}/bin/home-ops-bootstrap-jellyfin-plugins";
      };
    };
  };
}
