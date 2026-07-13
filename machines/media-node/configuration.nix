{
  imports = [
    ../../shared
    ./host.nix
    ./disk.nix
    ./secrets.nix
    ./nas-client.nix
    ./services/media/shared.nix
    ./services/media/downloads.nix
    ./services/media/movies-tv.nix
    ./services/media/arr-download-clients.nix
    ./services/media/prowlarr-bootstrap.nix
    ./services/media/configarr.nix
    ./services/media/qbit-manage.nix
    ./services/media/unpackerr.nix
    ./services/media/seerr-bootstrap.nix
    ./services/media/books.nix
    ./services/media/music.nix
    ./services/ingress.nix
  ];

  networking.hostName = "media-node";

  # Prefer the Tailscale/MagicDNS name once the host has joined the tailnet.
  clan.core.networking.targetHost = "root@media-node";

  homeOps = {
    secrets.enable = true;

    nas = {
      enable = true;
      host = "10.10.10.2";
      export = "/volume1/media-stack";
      mountPoint = "/mnt/nas/data";
    };

    media = {
      shared.enable = true;

      downloads = {
        sabnzbd.enable = true;
        gluetun.environmentFile = "/var/lib/home-ops/secrets/gluetun-env";
        qbittorrent = {
          enable = true;
        };
      };

      moviesTv.enable = true;
      arrDownloadClients.enable = true;
      prowlarrBootstrap.enable = true;
      configarr.enable = true;
      qbitManage.enable = true;
      unpackerr.enable = true;
      seerrBootstrap.enable = true;
      books.enable = true;
      music.enable = true;
    };

    # Tailscale-first access for now. Enable ingress only after real hostnames
    # point at this machine and certificate issuance is expected to work.
    ingress.enable = false;
  };

  system.stateVersion = "26.05";
}
