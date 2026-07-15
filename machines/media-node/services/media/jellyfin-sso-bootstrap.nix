{ config, lib, pkgs, ... }:

let
  cfg = config.homeOps.media.jellyfinSsoBootstrap;
  # Static XML template with a sentinel where the OIDC client secret is
  # substituted at runtime. Field set mirrors what the plugin actually writes
  # when configured via the admin UI (SSO-Auth plugin v4.0.0.x).
  xmlTemplate = pkgs.writeText "sso-auth.xml.tpl" ''
    <?xml version="1.0" encoding="utf-8"?>
    <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <SamlConfigs />
      <OidConfigs>
        <item>
          <key>
            <string>${cfg.providerName}</string>
          </key>
          <value>
            <PluginConfiguration>
              <OidEndpoint>${cfg.oidcEndpoint}</OidEndpoint>
              <OidClientId>${cfg.clientId}</OidClientId>
              <OidSecret>@OID_SECRET@</OidSecret>
              <Enabled>true</Enabled>
              <EnableAuthorization>false</EnableAuthorization>
              <EnableAllFolders>true</EnableAllFolders>
              <EnabledFolders />
              <AdminRoles />
              <Roles />
              <EnableFolderRoles>false</EnableFolderRoles>
              <EnableLiveTvRoles>false</EnableLiveTvRoles>
              <EnableLiveTv>false</EnableLiveTv>
              <EnableLiveTvManagement>false</EnableLiveTvManagement>
              <LiveTvRoles />
              <LiveTvManagementRoles />
              <FolderRoleMappings />
              <OidScopes>
                <string>openid</string>
                <string>profile</string>
                <string>email</string>
                <string>groups</string>
              </OidScopes>
              <PortOverride xsi:nil="true" />
              <NewPath>false</NewPath>
              <CanonicalLinks />
              <DefaultUsernameClaim>preferred_username</DefaultUsernameClaim>
              <DisableHttps>false</DisableHttps>
              <DisablePushedAuthorization>true</DisablePushedAuthorization>
              <DoNotValidateEndpoints>false</DoNotValidateEndpoints>
              <DoNotValidateIssuerName>false</DoNotValidateIssuerName>
              <DoNotLoadProfile>false</DoNotLoadProfile>
            </PluginConfiguration>
          </value>
        </item>
      </OidConfigs>
    </PluginConfiguration>
  '';
  seed = pkgs.writeShellApplication {
    name = "home-ops-jellyfin-sso-bootstrap";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gnused
      pkgs.systemd
    ];
    text = ''
      dst=/var/lib/jellyfin/plugins/configurations/SSO-Auth.xml
      secret_file=${cfg.clientSecretFile}
      tmp="$(mktemp)"
      jellyfin_stopped=false
      cleanup() {
        rm -f "$tmp"
        if [ "$jellyfin_stopped" = true ]; then
          systemctl start jellyfin.service || true
        fi
      }
      trap cleanup EXIT
      # Seed once: if the plugin config already exists, leave it alone. This
      # is a bootstrap, not an enforcer — once seeded, the admin owns the file
      # (any SSO settings changed in the Jellyfin UI must survive reboots).
      if [ -e "$dst" ]; then
        exit 0
      fi

      secret="$(cat "$secret_file")"
      # sed -e "s|A|B|" isn't safe if $secret contains |, but our hex-only
      # secrets never do; still play it safe with a distinctive sentinel.
      sed "s|@OID_SECRET@|$secret|" ${xmlTemplate} > "$tmp"

      # Write while Jellyfin is down: the SSO plugin persists its in-memory
      # config on shutdown and would clobber a file written while it runs.
      # The restart also makes Jellyfin load the freshly-installed plugin DLL,
      # which the plugin bootstrap deliberately doesn't do.
      systemctl stop jellyfin.service
      jellyfin_stopped=true
      install -D -m 0640 -o jellyfin -g media "$tmp" "$dst"
      systemctl start jellyfin.service
      jellyfin_stopped=false
    '';
  };
in
{
  options.homeOps.media.jellyfinSsoBootstrap = {
    enable = lib.mkEnableOption "Jellyfin SSO plugin config bootstrap";
    providerName = lib.mkOption {
      type = lib.types.str;
      default = "authelia";
      description = "Provider name — becomes the /sso/OID/start/<name> URL segment.";
    };
    oidcEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.lawing.net";
    };
    clientId = lib.mkOption {
      type = lib.types.str;
      default = "jellyfin";
    };
    clientSecretFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.homeOps.secrets.directory}/authelia-oidc-jellyfin-secret";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeOps.media.jellyfinPlugins.enable;
        message = "homeOps.media.jellyfinSsoBootstrap requires homeOps.media.jellyfinPlugins.enable (the plugin has to be installed first).";
      }
    ];

    systemd.services.home-ops-jellyfin-sso-bootstrap = {
      description = "Seed the Jellyfin SSO-Auth plugin config with Authelia client credentials";
      # Runs on every boot; skips silently until both the plugin is installed
      # AND the OIDC client secret has been generated by runtime-secrets.
      wantedBy = [ "multi-user.target" ];
      after = [
        "home-ops-runtime-secrets.service"
        "home-ops-jellyfin-plugins.service"
        "jellyfin.service"
      ];
      # wants=, not requires=: the plugins bootstrap can transiently fail
      # (60s Jellyfin-ping timeout, external plugin-manifest fetches), and a
      # hard requires= would cancel SSO seeding on any such blip. Ordered
      # after it so it runs post-install when it does succeed; the
      # ConditionPathExists on the plugin API key still gates a fresh box.
      wants = [
        "home-ops-runtime-secrets.service"
        "home-ops-jellyfin-plugins.service"
        "jellyfin.service"
      ];
      unitConfig.ConditionPathExists = [
        cfg.clientSecretFile
        config.homeOps.media.jellyfinPlugins.apiKeyFile
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${seed}/bin/home-ops-jellyfin-sso-bootstrap";
        RemainAfterExit = true;
      };
    };
  };
}
