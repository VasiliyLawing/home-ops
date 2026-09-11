{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeOps.media.sportarr;
  shared = config.homeOps.media.shared;
  secrets = config.homeOps.secrets;
in
{
  options.homeOps.media.sportarr = {
    enable = lib.mkEnableOption "Sportarr — sports event PVR (Sonarr fork)";
    image = lib.mkOption {
      type = lib.types.str;
      default = "sportarr/sportarr:4.1.7.1117";
      description = "Pinned Sportarr container image.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/home-ops/sportarr";
      description = "Local Sportarr config/database directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = shared.enable;
        message = "homeOps.media.sportarr requires homeOps.media.shared.enable for the NAS-backed /data root.";
      }
      {
        assertion = secrets.enable;
        message = "homeOps.media.sportarr requires homeOps.secrets.enable to export its API key.";
      }
    ];

    # Sportarr generates its own API key on first start. Unlike the native Arrs
    # we don't seed config.xml (the seeder forces AuthenticationMethod=External,
    # and Sportarr 401s non-local clients in that mode, which would break
    # Tailscale access). Instead export the key it chose so the Prowlarr
    # bootstrapper can link it. Not RemainAfterExit: every unit that Requires
    # this re-runs the export, so a regenerated key is picked up on the next
    # bootstrap timer tick.
    systemd.services.home-ops-sportarr-api-key = {
      description = "Export Sportarr's self-generated API key for Home Ops bootstrappers";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker-sportarr.service" ];
      wants = [ "docker-sportarr.service" ];
      path = [
        pkgs.coreutils
        pkgs.gnused
      ];
      script = ''
        cfg=${cfg.dataDir}/config.xml
        out=${secrets.directory}/sportarr-api-key
        for _ in $(seq 1 60); do
          key=$(sed -n 's#.*<ApiKey>\(.*\)</ApiKey>.*#\1#p' "$cfg" 2>/dev/null || true)
          if [ -n "$key" ]; then
            printf '%s\n' "$key" | install -m 0600 -o root -g root /dev/stdin "$out"
            exit 0
          fi
          sleep 2
        done
        echo "Sportarr never wrote an API key to $cfg" >&2
        exit 1
      '';
      serviceConfig.Type = "oneshot";
    };

    # 0700: config.xml carries the API key and Sportarr writes it 0664.
    # home-ops-sportarr-api-key reads it as root, so nothing else needs in.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 homeops media -"
    ];

    # Same NAS-mount guard as Sonarr/Radarr: never start against a missing /data.
    systemd.services.docker-sportarr.unitConfig.RequiresMountsFor = [ shared.dataRoot ];

    virtualisation.oci-containers.containers.sportarr = {
      image = cfg.image;
      autoStart = true;
      environment = {
        PUID = "1000";
        PGID = "1001";
        UMASK = "002";
        TZ = config.time.timeZone;
      };
      volumes = [
        "${cfg.dataDir}:/config"
        "${shared.dataRoot}:/data"
      ];
      # Host networking on Sportarr's fixed port 1867: Prowlarr/qBittorrent/
      # SABnzbd are reachable at plain 127.0.0.1 from inside the container, and
      # trustedInterfaces=tailscale0 gates the UI (LAN blocked by the firewall).
      # Prowlarr links it via home-ops-prowlarr-bootstrap (Sonarr-type app).
      # Download clients are set once in the UI: Sportarr has no
      # /downloadclient/schema endpoint, so arr-download-clients can't drive it.
      extraOptions = [ "--network=host" ];
    };
  };
}
