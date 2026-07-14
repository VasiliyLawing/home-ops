{ config, lib, pkgs, ... }:

let
  cfg = config.homeOps.authelia;
  instanceName = "main";
  stateDir = "/var/lib/authelia-${instanceName}";
  autheliaPkg = config.services.authelia.instances.${instanceName}.package;
  seedUsers = pkgs.writeShellApplication {
    name = "home-ops-authelia-seed-users";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      autheliaPkg
    ];
    text = ''
      users_file="${stateDir}/users.yml"
      if [ -s "$users_file" ]; then
        exit 0
      fi
      install -d -m 0750 -o authelia-${instanceName} -g authelia-${instanceName} "${stateDir}"
      admin_password="$(cat /var/lib/home-ops/secrets/authelia-admin-password)"
      password_hash="$(authelia crypto hash generate argon2 --password "$admin_password" --no-confirm | awk -F': ' '/^Digest:/ {print $2}')"
      umask 077
      cat > "$users_file" <<EOF
      users:
        ${cfg.adminUsername}:
          disabled: false
          displayname: "${cfg.adminDisplayName}"
          password: "$password_hash"
          email: ${cfg.adminEmail}
          groups:
            - admins
      EOF
      chown authelia-${instanceName}:authelia-${instanceName} "$users_file"
      chmod 0600 "$users_file"
    '';
  };
in
{
  options.homeOps.authelia = {
    enable = lib.mkEnableOption "Authelia forward-auth gateway for public services";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "lawing.net";
      description = "Cookie parent domain shared across protected hostnames.";
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = "auth.lawing.net";
      description = "External hostname Caddy exposes Authelia on.";
    };
    port = lib.mkOption {
      type = lib.types.int;
      default = 9091;
    };
    adminUsername = lib.mkOption {
      type = lib.types.str;
      default = "lawing";
    };
    adminDisplayName = lib.mkOption {
      type = lib.types.str;
      default = "Vasiliy Lawing";
    };
    adminEmail = lib.mkOption {
      type = lib.types.str;
      default = "vblawing@gmail.com";
    };
    protectedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Hostnames that require two-factor auth via Authelia.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.secrets.enable;
        message = "homeOps.authelia requires homeOps.secrets.enable.";
      }
    ];

    services.authelia.instances.${instanceName} = {
      enable = true;
      secrets = {
        jwtSecretFile = "/var/lib/home-ops/secrets/authelia-jwt-secret";
        storageEncryptionKeyFile = "/var/lib/home-ops/secrets/authelia-storage-encryption-key";
      };
      settings = {
        server.address = "tcp://127.0.0.1:${toString cfg.port}/";
        log.level = "info";
        totp.issuer = cfg.domain;
        authentication_backend.file = {
          path = "${stateDir}/users.yml";
          password.algorithm = "argon2id";
        };
        session.cookies = [
          {
            domain = cfg.domain;
            authelia_url = "https://${cfg.host}";
            default_redirection_url = "https://${cfg.domain}";
          }
        ];
        storage.local.path = "${stateDir}/db.sqlite3";
        notifier.filesystem.filename = "${stateDir}/notification.txt";
        access_control = {
          default_policy = "deny";
          rules =
            [
              {
                domain = cfg.host;
                policy = "bypass";
              }
            ]
            ++ map (h: {
              domain = h;
              policy = "two_factor";
            }) cfg.protectedHosts;
        };
      };
    };

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 authelia-${instanceName} authelia-${instanceName} -"
    ];

    systemd.services.home-ops-authelia-seed = {
      description = "Seed initial Authelia admin user from generated password";
      wantedBy = [ "authelia-${instanceName}.service" ];
      before = [ "authelia-${instanceName}.service" ];
      after = [ "home-ops-runtime-secrets.service" ];
      requires = [ "home-ops-runtime-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${seedUsers}/bin/home-ops-authelia-seed-users";
      };
    };
  };
}
