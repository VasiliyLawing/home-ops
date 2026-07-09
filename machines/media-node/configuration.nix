{
  imports = [
    ../../modules/base.nix
    ../../modules/disk.nix
    ../../modules/secrets.nix
    ../../modules/nas-client.nix
    ../../modules/media/shared.nix
    ../../modules/media/downloads.nix
    ../../modules/media/movies-tv.nix
    ../../modules/media/books.nix
    ../../modules/media/music.nix
    ../../modules/ingress.nix
  ];

  networking.hostName = "media-node";

  # Prefer the Tailscale/MagicDNS name once the host has joined the tailnet.
  clan.core.networking.targetHost = "root@media-node";

  homeOps = {
    secrets.enable = true;

    nas = {
      enable = true;
      # Filler until the NAS receives its final static address.
      host = "192.168.1.250";
      export = "/volume1/media-stack";
    };

    media = {
      shared.enable = true;

      downloads = {
        sabnzbd.enable = true;
        # Enable after filling in the WireGuard provider values below.
        qbittorrent = {
          enable = false;
          vpn = {
            privateKeyFile = "/run/secrets/qbittorrent-wg-private-key";
            address = "10.64.0.2/32";
            peerPublicKey = "REPLACE_WITH_WIREGUARD_PEER_PUBLIC_KEY";
            endpoint = "REPLACE_WITH_WIREGUARD_ENDPOINT:51820";
          };
        };
      };

      moviesTv.enable = true;
      books.enable = true;
      music.enable = true;
    };

    ingress.enable = true;
  };

  system.stateVersion = "26.05";
}
