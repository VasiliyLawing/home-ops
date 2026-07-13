{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.bazarrBootstrap;
  bootstrapBazarr = pkgs.buildGoModule {
    pname = "home-ops-bootstrap-bazarr";
    version = "0.1.0";
    src = ../../scripts/runtime-secrets/bazarr-bootstrap;
    vendorHash = null;
    env.CGO_ENABLED = "0";
    postInstall = ''
      if [ -x "$out/bin/bazarr-bootstrap" ]; then
        mv "$out/bin/bazarr-bootstrap" "$out/bin/home-ops-bootstrap-bazarr"
      elif [ -x "$out/bin/home-ops-bazarr-bootstrap" ]; then
        mv "$out/bin/home-ops-bazarr-bootstrap" "$out/bin/home-ops-bootstrap-bazarr"
      else
        echo "Could not find Bazarr bootstrap binary. Available binaries:" >&2
        ls -la "$out/bin" >&2
        exit 1
      fi
    '';
  };
in
{
  options.homeOps.media.bazarrBootstrap = {
    enable = lib.mkEnableOption "Bazarr Sonarr/Radarr settings bootstrap";
    configFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/bazarr/config/config.yaml";
      description = "Bazarr config.yaml path.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.moviesTv.enable;
        message = "homeOps.media.bazarrBootstrap requires homeOps.media.moviesTv.enable.";
      }
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.media.bazarrBootstrap requires homeOps.secrets.enable.";
      }
    ];

    users = {
      groups.bazarr = { };
      users.bazarr = {
        description = "Bazarr service user";
        isSystemUser = true;
        group = "bazarr";
      };
    };

    system.activationScripts.homeOpsBazarrStateDir = ''
      if [ -L /var/lib/bazarr ]; then
        target="$(readlink -f /var/lib/bazarr || true)"
        rm -f /var/lib/bazarr
        if [ -n "$target" ] && [ -d "$target" ]; then
          mv "$target" /var/lib/bazarr
        else
          install -d -m 0750 -o bazarr -g bazarr /var/lib/bazarr
        fi
      else
        install -d -m 0750 -o bazarr -g bazarr /var/lib/bazarr
      fi
      install -d -m 0750 -o bazarr -g bazarr /var/lib/bazarr/config
      chown -R bazarr:bazarr /var/lib/bazarr
    '';

    systemd.services.bazarr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "bazarr";
      Group = "bazarr";
      StateDirectory = lib.mkForce "bazarr";
    };

    systemd.services.home-ops-bazarr-bootstrap = {
      description = "Bootstrap Bazarr Sonarr/Radarr settings";
      wantedBy = [ "multi-user.target" ];
      after = [
        "home-ops-runtime-secrets.service"
        "home-ops-arr-configs.service"
      ];
      requires = [
        "home-ops-runtime-secrets.service"
        "home-ops-arr-configs.service"
      ];
      before = [ "bazarr.service" ];
      environment = {
        HOME_OPS_BAZARR_CONFIG_FILE = cfg.configFile;
        HOME_OPS_SONARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/sonarr-api-key";
        HOME_OPS_RADARR_API_KEY_FILE = "${config.homeOps.secrets.directory}/radarr-api-key";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${bootstrapBazarr}/bin/home-ops-bootstrap-bazarr";
        ExecStartPost = "${pkgs.coreutils}/bin/chown bazarr:bazarr ${cfg.configFile}";
        RemainAfterExit = true;
      };
    };

    systemd.services.bazarr = {
      requires = [ "home-ops-bazarr-bootstrap.service" ];
      after = [ "home-ops-bazarr-bootstrap.service" ];
    };
  };
}
