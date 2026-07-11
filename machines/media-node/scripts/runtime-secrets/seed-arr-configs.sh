set -eu

: "${HOME_OPS_ARR_CONFIGS_FILE:?}"

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

seed_config() {
  app="$1"
  instance="$2"
  port="$3"
  config_file="$4"
  api_key_file="$5"
  owner="$6"
  group="$7"

  if [ ! -r "$api_key_file" ]; then
    echo "Missing API key file for $app: $api_key_file" >&2
    return 1
  fi

  api_key="$(cat "$api_key_file" | xml_escape)"
  install -d -m 0750 -o "$owner" -g "$group" "$(dirname "$config_file")"

  if [ ! -e "$config_file" ]; then
    cat > "$config_file" <<EOF
<Config>
  <BindAddress>*</BindAddress>
  <Port>$port</Port>
  <SslPort>0</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>False</LaunchBrowser>
  <ApiKey>$api_key</ApiKey>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>
  <Branch>main</Branch>
  <LogLevel>info</LogLevel>
  <SslCertPath></SslCertPath>
  <SslCertPassword></SslCertPassword>
  <UrlBase></UrlBase>
  <InstanceName>$instance</InstanceName>
  <UpdateMechanism>BuiltIn</UpdateMechanism>
</Config>
EOF
  elif grep -q '<ApiKey>.*</ApiKey>' "$config_file"; then
    sed -i "s#<ApiKey>.*</ApiKey>#<ApiKey>$api_key</ApiKey>#" "$config_file"
  else
    sed -i "0,/<Config>/s#<Config>#<Config>\\n  <ApiKey>$api_key</ApiKey>#" "$config_file"
  fi

  chmod 0640 "$config_file"
  chown "$owner:$group" "$config_file"
}

while IFS='|' read -r app instance port config_file api_key_file owner group; do
  case "$app" in
    ''|'#'*)
      continue
      ;;
  esac
  seed_config "$app" "$instance" "$port" "$config_file" "$api_key_file" "$owner" "$group"
done < "$HOME_OPS_ARR_CONFIGS_FILE"
