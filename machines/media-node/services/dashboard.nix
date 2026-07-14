{ config, lib, ... }:

let
  cfg = config.homeOps.dashboard;
in
{
  options.homeOps.dashboard = {
    enable = lib.mkEnableOption "Homepage dashboard tying the whole stack together";
    host = lib.mkOption {
      type = lib.types.str;
      default = "home.lawing.net";
      description = "External hostname Caddy exposes Homepage on. Also becomes HOMEPAGE_ALLOWED_HOSTS.";
    };
    port = lib.mkOption {
      type = lib.types.int;
      default = 3000;
    };
  };

  config = lib.mkIf cfg.enable {
    services.homepage-dashboard = {
      enable = true;
      listenPort = cfg.port;
      openFirewall = false; # Caddy fronts it; nothing on LAN should reach 3000 directly
      allowedHosts = cfg.host;
      settings = {
        title = "home ops";
        headerStyle = "clean";
        color = "slate";
        theme = "dark";
        # Widgets sit at the top; datetime + a greeting is the minimum viable dashboard.
      };
      widgets = [
        { resources = { cpu = true; memory = true; disk = "/"; }; }
        { datetime = { text_size = "xl"; format = { timeStyle = "short"; dateStyle = "short"; }; }; }
      ];
      services = [
        {
          Media = [
            {
              Jellyfin = {
                href = "https://media.lawing.net";
                description = "Streaming";
                icon = "jellyfin.svg";
              };
            }
            {
              Seerr = {
                href = "https://media.request.lawing.net";
                description = "Requests";
                icon = "jellyseerr.svg";
              };
            }
          ];
        }
        {
          "Movies + TV" = [
            {
              Sonarr = {
                href = "http://media-node:8989";
                description = "TV PVR";
                icon = "sonarr.svg";
              };
            }
            {
              Radarr = {
                href = "http://media-node:7878";
                description = "Movie PVR";
                icon = "radarr.svg";
              };
            }
            {
              Bazarr = {
                href = "http://media-node:6767";
                description = "Subtitles";
                icon = "bazarr.svg";
              };
            }
            {
              Prowlarr = {
                href = "http://media-node:9696";
                description = "Indexers";
                icon = "prowlarr.svg";
              };
            }
          ];
        }
        {
          Music = [
            {
              Navidrome = {
                href = "http://media-node:4533";
                description = "Music streaming";
                icon = "navidrome.svg";
              };
            }
            {
              Lidarr = {
                href = "http://media-node:8686";
                description = "Music PVR";
                icon = "lidarr.svg";
              };
            }
            {
              slskd = {
                href = "http://media-node:5030";
                description = "Soulseek";
                icon = "slskd.svg";
              };
            }
          ];
        }
        {
          Books = [
            {
              Audiobookshelf = {
                href = "http://media-node:13378";
                description = "Audiobooks";
                icon = "audiobookshelf.svg";
              };
            }
            {
              "Calibre-Web" = {
                href = "http://media-node:8083";
                description = "E-books";
                icon = "calibre-web.svg";
              };
            }
          ];
        }
        {
          Downloads = [
            {
              qBittorrent = {
                href = "http://media-node:8081";
                description = "Torrents";
                icon = "qbittorrent.svg";
              };
            }
            {
              Sabnzbd = {
                href = "http://media-node:8080";
                description = "Usenet";
                icon = "sabnzbd.svg";
              };
            }
          ];
        }
        {
          Onboarding = [
            {
              Wizarr = {
                href = "https://invite.lawing.net";
                description = "Family & guest invites";
                icon = "wizarr.svg";
              };
            }
          ];
        }
      ];
    };
  };
}
