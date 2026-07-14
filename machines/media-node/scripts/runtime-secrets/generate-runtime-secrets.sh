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
      slskd-username)
        printf 'slskd-%s\n' "$(openssl rand -hex 6)" > "$path"
        ;;
      rsa4096)
        openssl genrsa -out "$path" 4096 2>/dev/null
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

read -ra secret_files <<< "$HOME_OPS_SECRET_FILES"
for name in "${secret_files[@]}"; do
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
    slskd-slsk-username)
      write_secret "$name" slskd-username
      ;;
    authelia-oidc-jwks-key)
      write_secret "$name" rsa4096
      ;;
    *)
      write_secret "$name" hex48
      ;;
  esac
done

# Consumers reference these env files unconditionally, so always write them;
# secrets absent from homeOps.secrets.files simply yield empty values.
read_secret() {
  if [ -r "$HOME_OPS_SECRET_DIRECTORY/$1" ]; then
    cat "$HOME_OPS_SECRET_DIRECTORY/$1"
  fi
}

sonarr_api_key="$(read_secret sonarr-api-key)"
radarr_api_key="$(read_secret radarr-api-key)"
prowlarr_api_key="$(read_secret prowlarr-api-key)"
lidarr_api_key="$(read_secret lidarr-api-key)"
qbittorrent_user="$(read_secret qbittorrent-webui-username)"
qbittorrent_password="$(read_secret qbittorrent-webui-password)"
slskd_slsk_username="$(read_secret slskd-slsk-username)"
slskd_slsk_password="$(read_secret slskd-slsk-password)"
slskd_web_password="$(read_secret slskd-web-password)"
slskd_api_key="$(read_secret slskd-api-key)"

cat > "$HOME_OPS_SECRET_DIRECTORY/arr-api-keys.env" <<EOF
SONARR_API_KEY=$sonarr_api_key
RADARR_API_KEY=$radarr_api_key
PROWLARR_API_KEY=$prowlarr_api_key
LIDARR_API_KEY=$lidarr_api_key
EOF

cat > "$HOME_OPS_SECRET_DIRECTORY/unpackerr-env" <<EOF
UN_SONARR_0_API_KEY=$sonarr_api_key
UN_RADARR_0_API_KEY=$radarr_api_key
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

# Soulseek accounts are registered implicitly: slskd's first login with these
# generated credentials creates the account. To use an existing Soulseek
# identity instead, overwrite slskd-slsk-username/-password before first start.
cat > "$HOME_OPS_SECRET_DIRECTORY/slskd-env" <<EOF
SLSKD_SLSK_USERNAME=$slskd_slsk_username
SLSKD_SLSK_PASSWORD=$slskd_slsk_password
SLSKD_USERNAME=admin
SLSKD_PASSWORD=$slskd_web_password
SLSKD_API_KEY=role=ReadWrite;cidr=0.0.0.0/0,::/0;$slskd_api_key
EOF

chmod 0600 \
  "$HOME_OPS_SECRET_DIRECTORY/arr-api-keys.env" \
  "$HOME_OPS_SECRET_DIRECTORY/unpackerr-env" \
  "$HOME_OPS_SECRET_DIRECTORY/qbittorrent-env" \
  "$HOME_OPS_SECRET_DIRECTORY/shelfmark-env" \
  "$HOME_OPS_SECRET_DIRECTORY/slskd-env"
chown root:root \
  "$HOME_OPS_SECRET_DIRECTORY/arr-api-keys.env" \
  "$HOME_OPS_SECRET_DIRECTORY/unpackerr-env" \
  "$HOME_OPS_SECRET_DIRECTORY/qbittorrent-env" \
  "$HOME_OPS_SECRET_DIRECTORY/shelfmark-env" \
  "$HOME_OPS_SECRET_DIRECTORY/slskd-env"
