set -eu

install -d -m 0700 -o root -g root "$HOME_OPS_SECRET_DIRECTORY"

write_secret() {
  name="$1"
  generator="$2"
  path="$HOME_OPS_SECRET_DIRECTORY/$name"

  if [ ! -e "$path" ]; then
    case "$generator" in
      hex32)
        openssl rand -hex 16 > "$path"
        ;;
      hex48)
        openssl rand -hex 24 > "$path"
        ;;
      literal:*)
        printf '%s\n' "${generator#literal:}" > "$path"
        ;;
      *)
        echo "Unknown generator for $name: $generator" >&2
        return 1
        ;;
    esac
    chmod 0600 "$path"
    chown root:root "$path"
  fi
}

for name in $HOME_OPS_SECRET_FILES; do
  case "$name" in
    *api-key)
      write_secret "$name" hex32
      ;;
    qbittorrent-webui-username)
      write_secret "$name" literal:admin
      ;;
    qbittorrent-webui-password)
      write_secret "$name" hex48
      ;;
    *)
      write_secret "$name" hex48
      ;;
  esac
done

sonarr_api_key="$(cat "$HOME_OPS_SECRET_DIRECTORY/sonarr-api-key")"
radarr_api_key="$(cat "$HOME_OPS_SECRET_DIRECTORY/radarr-api-key")"
prowlarr_api_key="$(cat "$HOME_OPS_SECRET_DIRECTORY/prowlarr-api-key")"
lidarr_api_key="$(cat "$HOME_OPS_SECRET_DIRECTORY/lidarr-api-key")"
qbittorrent_user="$(cat "$HOME_OPS_SECRET_DIRECTORY/qbittorrent-webui-username")"
qbittorrent_password="$(cat "$HOME_OPS_SECRET_DIRECTORY/qbittorrent-webui-password")"

cat > "$HOME_OPS_SECRET_DIRECTORY/arr-api-keys.env" <<EOF
SONARR_API_KEY=$sonarr_api_key
RADARR_API_KEY=$radarr_api_key
PROWLARR_API_KEY=$prowlarr_api_key
LIDARR_API_KEY=$lidarr_api_key
EOF

cat > "$HOME_OPS_SECRET_DIRECTORY/buildarr-secret.yml" <<EOF
---
sonarr:
  instances:
    Sonarr:
      api_key: "$sonarr_api_key"
      settings:
        download_clients:
          definitions:
            "qBittorrent":
              username: "$qbittorrent_user"
              password: "$qbittorrent_password"

radarr:
  instances:
    Radarr:
      api_key: "$radarr_api_key"
      settings:
        download_clients:
          definitions:
            "qBittorrent":
              username: "$qbittorrent_user"
              password: "$qbittorrent_password"

prowlarr:
  api_key: "$prowlarr_api_key"
EOF

cat > "$HOME_OPS_SECRET_DIRECTORY/qbittorrent-env" <<EOF
QBIT_USER=$qbittorrent_user
QBIT_PASS=$qbittorrent_password
EOF

cat > "$HOME_OPS_SECRET_DIRECTORY/shelfmark-env" <<EOF
PROWLARR_API_KEY=$prowlarr_api_key
QBITTORRENT_USERNAME=$qbittorrent_user
QBITTORRENT_PASSWORD=$qbittorrent_password
EOF

chmod 0600 \
  "$HOME_OPS_SECRET_DIRECTORY/arr-api-keys.env" \
  "$HOME_OPS_SECRET_DIRECTORY/buildarr-secret.yml" \
  "$HOME_OPS_SECRET_DIRECTORY/qbittorrent-env" \
  "$HOME_OPS_SECRET_DIRECTORY/shelfmark-env"
chown root:root \
  "$HOME_OPS_SECRET_DIRECTORY/arr-api-keys.env" \
  "$HOME_OPS_SECRET_DIRECTORY/buildarr-secret.yml" \
  "$HOME_OPS_SECRET_DIRECTORY/qbittorrent-env" \
  "$HOME_OPS_SECRET_DIRECTORY/shelfmark-env"
