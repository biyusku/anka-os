# ANKA Home Manager configuration — user-level dotfiles and packages
{ config, lib, pkgs, ... }:

{
  home.stateVersion = "24.11";

  # ── Shell ─────────────────────────────────────────────────────────────
  programs.zsh = {
    enable            = true;
    enableCompletion  = true;
    autosuggestion.enable    = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll   = "eza -la --icons";
      ls   = "eza --icons";
      cat  = "bat";
      du   = "duf";
      grep = "rg";
      find = "fd";
      # ANKA shortcuts
      anka-rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#anka";
      anka-update  = "sudo nix flake update /etc/nixos && anka-rebuild";
    };

    initContent = ''
      # ANKA banner
      echo "🦅 ANKA OS — $(nixos-version 2>/dev/null || echo 'NixOS')"
    '';
    dotDir = config.home.homeDirectory;
  };

  programs.starship = {
    enable   = true;
    settings = {
      format = "$username$hostname$directory$git_branch$git_status$nix_shell$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](bold green)";
        error_symbol   = "[❯](bold red)";
      };
      nix_shell.symbol = "❄️ ";
    };
  };

  # ── Git ───────────────────────────────────────────────────────────────
  programs.git = {
    enable   = true;
    settings = {
      user.name  = "ANKA User";
      user.email = "user@anka.local";
      init.defaultBranch   = "main";
      push.autoSetupRemote = true;
      pull.rebase          = false;
    };
  };

  # ── User packages ─────────────────────────────────────────────────────
  home.packages = with pkgs; [
    eza
    bat
    fd
    ripgrep
    fzf
    duf
    starship
  ];

  # ── XDG directories ───────────────────────────────────────────────────
  xdg = {
    enable              = true;
    userDirs = {
      enable                = true;
      createDirectories     = true;
      setSessionVariables   = true;
      documents          = "${config.home.homeDirectory}/Documents";
      download           = "${config.home.homeDirectory}/Downloads";
      music              = "${config.home.homeDirectory}/Music";
      pictures           = "${config.home.homeDirectory}/Pictures";
      videos             = "${config.home.homeDirectory}/Videos";
    };
  };

  # Home Manager manages itself
  programs.home-manager.enable = true;
}