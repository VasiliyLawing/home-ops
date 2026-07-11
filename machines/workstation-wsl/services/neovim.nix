{ config, lib, pkgs, ... }:

let
  cfg = config.homeOps.dev.neovim;
in
{
  options.homeOps.dev.neovim.enable = lib.mkEnableOption "Neovim workstation tooling";

  config = lib.mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      withNodeJs = true;
      withPython3 = true;
    };

    environment.systemPackages = [
      pkgs.bash-language-server
      pkgs.lua-language-server
      pkgs.nil
      pkgs.nixd
      pkgs.pyright
      pkgs.ripgrep
      pkgs.ruff
      pkgs.shellcheck
      pkgs.shfmt
      pkgs.stylua
      pkgs.taplo
      pkgs.tree-sitter
      pkgs.typescript-language-server
      pkgs.vscode-langservers-extracted
    ];

    environment.sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };
}
