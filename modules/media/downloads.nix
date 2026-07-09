{ config, lib, pkgs, ... }:

let
  cfg = config.homeOps.media.downloads;
  namespace = "qbittorrent";
  hostInterface = "qbittorrent-host";
  namespaceInterface = "qbittorrent-net";
  wireguardInterface = "qbittorrent-wg";
  cidrHost = value: builtins.head (lib.splitString "/" value);

  stopVpnNamespace = pkgs.writeShellScript "qbittorrent-vpn-netns-stop" ''
    set +e
    ${pkgs.iproute2}/bin/ip netns pids ${namespace} 2>/dev/null | ${pkgs.findutils}/bin/xargs -r kill
    ${pkgs.iproute2}/bin/ip netns del ${namespace} 2>/dev/null
    ${pkgs.iproute2}/bin/ip link del ${hostInterface} 2>/dev/null
  '';

  startVpnNamespace = pkgs.writeShellScript "qbittorrent-vpn-netns-start" ''
    set -eu
    ${stopVpnNamespace} || true
    ${pkgs.iproute2}/bin/ip netns add ${namespace}
    ${pkgs.iproute2}/bin/ip link add ${hostInterface} type veth peer name ${namespaceInterface}
    ${pkgs.iproute2}/bin/ip addr add ${cfg.qbittorrent.hostAddress} dev ${hostInterface}
    ${pkgs.iproute2}/bin/ip link set ${hostInterface} up
    ${pkgs.iproute2}/bin/ip link set ${namespaceInterface} netns ${namespace}
    ${pkgs.iproute2}/bin/ip -n ${namespace} addr add ${cfg.qbittorrent.namespaceAddress} dev ${namespaceInterface}
    ${pkgs.iproute2}/bin/ip -n ${namespace} link set lo up
    ${pkgs.iproute2}/bin/ip -n ${namespace} link set ${namespaceInterface} up
    install -d -m 0755 /etc/netns/${namespace}
    printf 'nameserver %s\n' '${cfg.qbittorrent.vpn.dns}' > /etc/netns/${namespace}/resolv.conf

    ${pkgs.iproute2}/bin/ip -n ${namespace} link add ${wireguardInterface} type wireguard
    ${pkgs.iproute2}/bin/ip netns exec ${namespace} ${pkgs.wireguard-tools}/bin/wg set ${wireguardInterface} \
      private-key ${cfg.qbittorrent.vpn.privateKeyFile} \
      peer ${cfg.qbittorrent.vpn.peerPublicKey} \
      endpoint ${cfg.qbittorrent.vpn.endpoint} \
      allowed-ips ${lib.concatStringsSep "," cfg.qbittorrent.vpn.allowedIPs} \
      persistent-keepalive ${toString cfg.qbittorrent.vpn.persistentKeepalive}
    ${pkgs.iproute2}/bin/ip -n ${namespace} addr add ${cfg.qbittorrent.vpn.address} dev ${wireguardInterface}
    ${pkgs.iproute2}/bin/ip -n ${namespace} link set ${wireguardInterface} up
    ${pkgs.iproute2}/bin/ip -n ${namespace} route add default dev ${wireguardInterface}

    ${pkgs.iproute2}/bin/ip netns exec ${namespace} ${pkgs.nftables}/bin/nft -f - <<'NFT'
    flush ruleset
    table inet qbittorrent_killswitch {
      chain input {
        type filter hook input priority 0; policy drop;
        iifname "lo" accept
        iifname "${wireguardInterface}" accept
        iifname "${namespaceInterface}" ip saddr ${cidrHost cfg.qbittorrent.hostAddress} tcp dport ${toString cfg.qbittorrent.webuiPort} accept
      }
      chain output {
        type filter hook output priority 0; policy drop;
        oifname "lo" accept
        meta l4proto udp ip daddr ${builtins.head (lib.splitString ":" cfg.qbittorrent.vpn.endpoint)} accept
        oifname "${wireguardInterface}" accept
        oifname "${namespaceInterface}" ip daddr ${cidrHost cfg.qbittorrent.hostAddress} tcp sport ${toString cfg.qbittorrent.webuiPort} accept
      }
    }
    NFT
  '';
in
{
  options.homeOps.media.downloads = {
    sabnzbd.enable = lib.mkEnableOption "SABnzbd directly on the host";
    qbittorrent = {
      enable = lib.mkEnableOption "qBittorrent isolated inside a WireGuard network namespace";
      webuiPort = lib.mkOption {
        type = lib.types.port;
        default = 8080;
      };
      torrentingPort = lib.mkOption {
        type = lib.types.port;
        default = 6881;
      };
      hostAddress = lib.mkOption {
        type = lib.types.str;
        default = "10.250.0.1/30";
      };
      namespaceAddress = lib.mkOption {
        type = lib.types.str;
        default = "10.250.0.2/30";
      };
      namespaceHost = lib.mkOption {
        type = lib.types.str;
        default = "10.250.0.2";
      };
      vpn = {
        privateKeyFile = lib.mkOption {
          type = lib.types.str;
          default = "/run/secrets/qbittorrent-wg-private-key";
        };
        address = lib.mkOption {
          type = lib.types.str;
          default = "10.64.0.2/32";
        };
        peerPublicKey = lib.mkOption {
          type = lib.types.str;
          default = "REPLACE_WITH_WIREGUARD_PEER_PUBLIC_KEY";
        };
        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "REPLACE_WITH_WIREGUARD_ENDPOINT:51820";
        };
        allowedIPs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "0.0.0.0/0" ];
        };
        dns = lib.mkOption {
          type = lib.types.str;
          default = "10.2.0.1";
        };
        persistentKeepalive = lib.mkOption {
          type = lib.types.int;
          default = 25;
        };
      };
    };
  };

  config = {
    assertions = [
      {
        assertion =
          !cfg.qbittorrent.enable
          || cfg.qbittorrent.vpn.peerPublicKey != "REPLACE_WITH_WIREGUARD_PEER_PUBLIC_KEY";
        message = "Set homeOps.media.downloads.qbittorrent.vpn.peerPublicKey before enabling qBittorrent.";
      }
      {
        assertion =
          !cfg.qbittorrent.enable
          || cfg.qbittorrent.vpn.endpoint != "REPLACE_WITH_WIREGUARD_ENDPOINT:51820";
        message = "Set homeOps.media.downloads.qbittorrent.vpn.endpoint before enabling qBittorrent.";
      }
    ];

    services.sabnzbd = lib.mkIf cfg.sabnzbd.enable {
      enable = true;
      group = "media";
      openFirewall = false;
    };

    environment.systemPackages = lib.mkIf cfg.qbittorrent.enable [
      pkgs.iproute2
      pkgs.nftables
      pkgs.wireguard-tools
    ];

    boot.kernelModules = lib.mkIf cfg.qbittorrent.enable [ "wireguard" ];

    services.qbittorrent = lib.mkIf cfg.qbittorrent.enable {
      enable = true;
      group = "media";
      openFirewall = false;
      webuiPort = cfg.qbittorrent.webuiPort;
      torrentingPort = cfg.qbittorrent.torrentingPort;
    };

    systemd.services.qbittorrent-vpn-netns = lib.mkIf cfg.qbittorrent.enable {
      description = "qBittorrent WireGuard network namespace";
      wantedBy = [ "multi-user.target" ];
      before = [ "qbittorrent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = startVpnNamespace;
        ExecStop = stopVpnNamespace;
      };
    };

    systemd.services.qbittorrent = lib.mkIf cfg.qbittorrent.enable {
      requires = [ "qbittorrent-vpn-netns.service" ];
      after = [ "qbittorrent-vpn-netns.service" ];
      bindsTo = [ "qbittorrent-vpn-netns.service" ];
      serviceConfig.NetworkNamespacePath = "/run/netns/${namespace}";
    };

    systemd.sockets.qbittorrent-web-proxy = lib.mkIf cfg.qbittorrent.enable {
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "127.0.0.1:${toString cfg.qbittorrent.webuiPort}" ];
    };

    systemd.services.qbittorrent-web-proxy = lib.mkIf cfg.qbittorrent.enable {
      description = "Host-local proxy to qBittorrent Web UI inside VPN namespace";
      requires = [ "qbittorrent.service" ];
      after = [ "qbittorrent.service" ];
      serviceConfig.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${cfg.qbittorrent.namespaceHost}:${toString cfg.qbittorrent.webuiPort}";
    };
  };
}
