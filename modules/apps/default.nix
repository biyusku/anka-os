# ANKA core applications — Flatpak, Bottles, essential tools
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.apps;
in
{
  options.anka.apps = {
    enable = lib.mkEnableOption "ANKA core application layer";

    flatpak = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Enable Flatpak (Flathub) for sandboxed app distribution.";
    };

    bottles = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Install Bottles (Wine prefix GUI manager).";
    };

    terminal = lib.mkOption {
      type    = lib.types.enum [ "konsole" "kitty" "alacritty" "wezterm" ];
      default = "konsole";
      description = "Default terminal emulator.";
    };

    browser = lib.mkOption {
      type    = lib.types.enum [ "firefox" "chromium" "brave" "librewolf" ];
      default = "firefox";
      description = "Default web browser.";
    };

    extraPackages = lib.mkOption {
      type    = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install system-wide.";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Flatpak ───────────────────────────────────────────────────────────
    services.flatpak.enable = lib.mkIf cfg.flatpak true;

    # Add Flathub remote on first boot
    system.activationScripts.flatpakFlathub = lib.mkIf cfg.flatpak {
      deps = [];
      text = ''
        if ${pkgs.flatpak}/bin/flatpak remotes 2>/dev/null | grep -q flathub; then
          true  # already configured
        else
          ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo || true
        fi
      '';
    };

    # ── Terminal ──────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; lib.concatLists [
      # Terminal
      (lib.optional (cfg.terminal == "konsole")  kdePackages.konsole)
      (lib.optional (cfg.terminal == "kitty")    kitty)
      (lib.optional (cfg.terminal == "alacritty") alacritty)
      (lib.optional (cfg.terminal == "wezterm")  wezterm)

      # Browser
      (lib.optional (cfg.browser == "firefox")   firefox)
      (lib.optional (cfg.browser == "chromium")  chromium)
      (lib.optional (cfg.browser == "brave")     brave)
      (lib.optional (cfg.browser == "librewolf") librewolf)

      # Bottles
      (lib.optional cfg.bottles bottles)

      # Core CLI tools (always installed)
      [
        git
        vim
        neovim
        htop
        fastfetch          # system info (neofetch successor)
        unzip
        p7zip
        ripgrep
        fd
        bat                # cat with syntax highlighting
        eza                # ls replacement
        fzf
        tmux
        rsync
        tree
        jq
        yq-go
        wget
        curl
        socat
      ]

      # Core GUI apps
      [
        libreoffice-qt6-fresh
        gimp
        vlc
        signal-desktop
        bitwarden-desktop  # password manager
        obsidian           # note taking
      ]

      # System utilities
      [
        lm_sensors         # hardware temperature
        inxi               # system info
        pciutils
        usbutils
        duf                # df replacement
        ncdu               # du replacement
        iotop
        btop
      ]

      cfg.extraPackages
    ];

    # ── Default applications (XDG MIME) ───────────────────────────────────
    xdg.mime.defaultApplications = {
      "text/html"                   = "${cfg.browser}.desktop";
      "x-scheme-handler/http"       = "${cfg.browser}.desktop";
      "x-scheme-handler/https"      = "${cfg.browser}.desktop";
      "application/pdf"             = "org.kde.okular.desktop";
      "image/png"                   = "org.kde.gwenview.desktop";
      "image/jpeg"                  = "org.kde.gwenview.desktop";
      "inode/directory"             = "org.kde.dolphin.desktop";
      "video/mp4"                   = "vlc.desktop";
      "video/x-matroska"            = "vlc.desktop";
      "audio/mpeg"                  = "vlc.desktop";
    };

    # ── Shell configuration ───────────────────────────────────────────────
    programs.zsh = {
      enable          = true;
      syntaxHighlighting.enable = true;
      autosuggestions.enable    = true;
      ohMyZsh = {
        enable  = true;
        theme   = "robbyrussell";
        plugins = [ "git" "sudo" "docker" "systemd" "z" ];
      };
    };

    # Use zsh as default shell
    users.defaultUserShell = pkgs.zsh;

    # ── nix / nixpkgs configuration ───────────────────────────────────────
    nix = {
      settings = {
        experimental-features  = [ "nix-command" "flakes" ];
        auto-optimise-store    = true;
        substituters           = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
          "https://chaotic-nyx.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n17rIDy40agHj12WfF+Gqk6SonIT8="
        ];
        warn-dirty = false;
      };
      gc = {
        automatic  = true;
        dates      = "weekly";
        options    = "--delete-older-than 14d";
      };
    };
  };
}