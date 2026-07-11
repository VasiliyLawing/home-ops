{ pkgs, ... }:

{
  wsl = {
    enable = true;
    defaultUser = "homeops";
    startMenuLaunchers = true;
    wslConf = {
      automount.root = "/mnt";
      interop.appendWindowsPath = false;
      network.generateHosts = true;
      network.generateResolvConf = true;
    };
  };

  networking = {
    hostName = "workstation-wsl";
    firewall.enable = false;
  };

  users.users.homeops.shell = pkgs.zsh;

  programs = {
    zsh = {
      enable = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
    };
    git.enable = true;
    ssh.startAgent = true;
  };

  services.tailscale.enable = false;
  services.openssh.enable = false;
  services.resolved.enable = false;

  environment.systemPackages = [
    pkgs.fd
    pkgs.fzf
    pkgs.jq
    pkgs.lazygit
    pkgs.ripgrep
    pkgs.tmux
    pkgs.tree
    pkgs.unzip
    pkgs.wget
    pkgs.zellij
    pkgs.zip
  ];
}
