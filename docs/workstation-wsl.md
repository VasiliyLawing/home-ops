# Workstation WSL

`workstation-wsl` is a NixOS-WSL dev machine for the Windows PC.

It lives entirely under:

```text
machines/workstation-wsl/
```

Its workstation-specific applications live under:

```text
machines/workstation-wsl/services/
```

It is separate from `media-node`:

- no Tailscale;
- no OpenSSH server;
- no media services;
- no NAS mount;
- no Disko install layout.

It provides:

- Neovim as the default editor;
- common CLI tools;
- language servers for Nix, Lua, Bash, TypeScript, Python, JSON/HTML/CSS;
- zsh, tmux, zellij, fzf, ripgrep, fd, lazygit.

## First install

Install or import a NixOS-WSL distro first, then apply this repo's config from
inside WSL:

```bash
sudo nixos-rebuild switch --flake .#workstation-wsl
```

If using Clan later:

```bash
clan machines update workstation-wsl
```

The workstation is intentionally local-only for now.
