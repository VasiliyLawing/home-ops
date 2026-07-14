{ config, lib, pkgs, ... }:

let
  cfg = config.homeOps.authelia;
  instanceName = "main";
  stateDir = "/var/lib/authelia-${instanceName}";
  autheliaPkg = config.services.authelia.instances.${instanceName}.package;
  # Extra users are supplied out-of-band via a TSV on the box so their names
  # and emails never enter git. Format (tabs, one user per line, # = comment):
  #   username<TAB>Displayname<TAB>email@example.com<TAB>groups[,groups...]
  # A random password per user is generated into
  # /var/lib/home-ops/secrets/authelia-password-<username> on first sight.
  seedUsers = pkgs.writeShellApplication {
    name = "home-ops-authelia-seed-users";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.openssl
      autheliaPkg
    ];
    text = ''
      users_file="${stateDir}/users.yml"
      tsv="${cfg.extraUsersFile}"
      secret_dir="/var/lib/home-ops/secrets"

      install -d -m 0750 -o authelia-${instanceName} -g authelia-${instanceName} "${stateDir}"

      hash_password() {
        authelia crypto hash generate argon2 --password "$1" --no-confirm \
          | awk -F': ' '/^Digest:/ {print $2}'
      }

      ensure_password_secret() {
        # $1 = username, $2 = existing password file (or "" to auto-generate)
        local name="$1" src="$2" path
        path="$secret_dir/authelia-password-$name"
        if [ ! -s "$path" ]; then
          if [ -n "$src" ] && [ -s "$src" ]; then
            install -m 0600 -o root -g root "$src" "$path"
          else
            umask 077
            openssl rand -hex 24 > "$path"
            chown root:root "$path"
          fi
        fi
        cat "$path"
      }

      write_user_block() {
        # $1 = username, $2 = displayname, $3 = email, $4 = comma-groups, $5 = password
        local u="$1" dn="$2" email="$3" groups_csv="$4" pw="$5" hash
        hash="$(hash_password "$pw")"
        {
          printf '  %s:\n' "$u"
          printf '    disabled: false\n'
          printf '    displayname: "%s"\n' "$dn"
          printf '    password: "%s"\n' "$hash"
          printf '    email: %s\n' "$email"
          printf '    groups:\n'
          for g in $(printf '%s' "$groups_csv" | tr ',' ' '); do
            printf '      - %s\n' "$g"
          done
        } >> "$tmp"
      }

      tmp="$(mktemp)"
      trap 'rm -f "$tmp"' EXIT
      printf 'users:\n' > "$tmp"

      admin_pw="$(ensure_password_secret ${cfg.adminUsername} "$secret_dir/authelia-admin-password")"
      write_user_block "${cfg.adminUsername}" "${cfg.adminDisplayName}" "${cfg.adminEmail}" "admins" "$admin_pw"

      if [ -f "$tsv" ]; then
        while IFS=$'\t' read -r u dn email groups_csv; do
          # skip blanks and comments
          case "$u" in '''|"#"*) continue;; esac
          [ -z "''${groups_csv:-}" ] && groups_csv="users"
          [ "$u" = "${cfg.adminUsername}" ] && continue  # admin already written
          user_pw="$(ensure_password_secret "$u" "")"
          write_user_block "$u" "$dn" "$email" "$groups_csv" "$user_pw"
        done < "$tsv"
      fi

      install -m 0600 -o authelia-${instanceName} -g authelia-${instanceName} "$tmp" "$users_file"

      # OIDC clients — one entry per registered app. Client secret must be
      # pbkdf2-hashed in Authelia's config; plaintext lives in the secret
      # file for the app-side plugin to consume verbatim.
      oidc_file="${stateDir}/oidc-clients.yml"
      jellyfin_secret="$(cat /var/lib/home-ops/secrets/authelia-oidc-jellyfin-secret)"
      jellyfin_secret_hash="$(authelia crypto hash generate pbkdf2 --variant sha512 --password "$jellyfin_secret" --no-confirm | awk -F': ' '/^Digest:/ {print $2}')"

      oidc_tmp="$(mktemp)"
      trap 'rm -f "$tmp" "$oidc_tmp"' EXIT
      cat > "$oidc_tmp" <<EOF
      identity_providers:
        oidc:
          claims_policies:
            default:
              id_token: [email, email_verified, preferred_username, name, groups]
          clients:
            - client_id: jellyfin
              client_name: Jellyfin
              client_secret: "$jellyfin_secret_hash"
              public: false
              authorization_policy: two_factor
              require_pkce: false
              redirect_uris:
                - https://${cfg.jellyfinHost}/sso/OID/redirect/authelia
              scopes: [openid, profile, groups, email]
              userinfo_signed_response_alg: none
              token_endpoint_auth_method: client_secret_post
      EOF
      install -m 0640 -o authelia-${instanceName} -g authelia-${instanceName} "$oidc_tmp" "$oidc_file"
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
    extraUsersFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/home-ops/authelia-users.tsv";
      description = ''
        Path on the box to a tab-separated user list. Not in git — populate
        by hand so family members' real names/emails stay off GitHub.
        Format (tabs): username<TAB>Displayname<TAB>email<TAB>groups(csv)
      '';
    };
    jellyfinHost = lib.mkOption {
      type = lib.types.str;
      default = "media.lawing.net";
      description = "External Jellyfin hostname — used to build the OIDC redirect URI.";
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
      # OIDC clients (currently just Jellyfin) are declared at runtime in
      # /var/lib/authelia-main/oidc-clients.yml because the client_secret has
      # to be pbkdf2-hashed by the authelia CLI at bootstrap time.
      settingsFiles = [ "${stateDir}/oidc-clients.yml" ];
      # Authelia runs as authelia-main and can't read root-owned secrets;
      # systemd LoadCredential (below) copies them to a per-service credentials
      # tmpfs owned by the service user.
      secrets = {
        jwtSecretFile = "/run/credentials/authelia-${instanceName}.service/jwt-secret";
        storageEncryptionKeyFile = "/run/credentials/authelia-${instanceName}.service/storage-encryption-key";
        oidcHmacSecretFile = "/run/credentials/authelia-${instanceName}.service/oidc-hmac-secret";
        oidcIssuerPrivateKeyFile = "/run/credentials/authelia-${instanceName}.service/oidc-jwks-key";
      };
      settings = {
        server.address = "tcp://127.0.0.1:${toString cfg.port}/";
        log.level = "info";
        totp.issuer = cfg.domain;
        authentication_backend = {
          # Reload users.yml automatically when the seed script rewrites it —
          # no authelia restart needed to add a family member.
          refresh_interval = "1m";
          file = {
            path = "${stateDir}/users.yml";
            watch = true;
            password.algorithm = "argon2id";
          };
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

    systemd.services."authelia-${instanceName}".serviceConfig.LoadCredential = [
      "jwt-secret:/var/lib/home-ops/secrets/authelia-jwt-secret"
      "storage-encryption-key:/var/lib/home-ops/secrets/authelia-storage-encryption-key"
      "oidc-hmac-secret:/var/lib/home-ops/secrets/authelia-oidc-hmac-secret"
      "oidc-jwks-key:/var/lib/home-ops/secrets/authelia-oidc-jwks-key"
    ];

    systemd.services.home-ops-authelia-seed = {
      description = "Seed Authelia users.yml from generated per-user passwords";
      wantedBy = [
        "authelia-${instanceName}.service"
        "multi-user.target"
      ];
      before = [ "authelia-${instanceName}.service" ];
      after = [ "home-ops-runtime-secrets.service" ];
      requires = [ "home-ops-runtime-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        ExecStart = "${seedUsers}/bin/home-ops-authelia-seed-users";
      };
    };
  };
}
