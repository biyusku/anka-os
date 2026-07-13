# ANKA desktop — KDE Plasma 6 on Wayland with PipeWire audio
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.desktop;
in
{
  options.anka.desktop = {
    enable = lib.mkEnableOption "ANKA desktop environment (KDE Plasma 6 Wayland)";

    session = lib.mkOption {
      type    = lib.types.enum [ "plasma6" "gnome" "hyprland" ];
      default = "plasma6";
      description = "Desktop session to install and enable.";
    };

    autoLogin = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = false;
        description = "Auto-login without password prompt.";
      };

      user = lib.mkOption {
        type    = lib.types.str;
        default = "anka";
        description = "User to auto-login as.";
      };
    };

    extraApps = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Install KDE extra applications (Dolphin, Konsole, Kate, Gwenview, etc.).";
    };

    wayland = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Force Wayland session (recommended for Plasma 6).";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Display server — SDDM on Wayland ──────────────────────────────────
    services.displayManager.sddm = {
      enable      = true;
      wayland.enable = cfg.wayland;
      theme       = "breeze";
      autoNumlock = true;
      settings = {
        Autologin = lib.mkIf cfg.autoLogin.enable {
          Session = "plasma.desktop";
          User    = cfg.autoLogin.user;
        };
      };
    };

    # ── KDE Plasma 6 ──────────────────────────────────────────────────────
    services.desktopManager.plasma6.enable =
      lib.mkIf (cfg.session == "plasma6") true;

    environment.plasma6.excludePackages = with pkgs.kdePackages; [
      plasma-browser-integration   # we'll use browser extensions instead
      oxygen                       # old Oxygen theme — Breeze is default
    ];

    # ── XDG portals (Wayland screen share, file picker) ───────────────────
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        kdePackages.xdg-desktop-portal-kde
        xdg-desktop-portal-gtk    # GTK app compatibility
      ];
    };

    # ── PipeWire audio ────────────────────────────────────────────────────
    services.pulseaudio.enable = false;   # PipeWire replaces PulseAudio

    services.pipewire = {
      enable            = true;
      alsa.enable       = true;
      alsa.support32Bit = true;   # 32-bit app (Wine, Steam) audio
      pulse.enable      = true;   # PulseAudio drop-in replacement
      jack.enable       = true;   # JACK for pro audio

      wireplumber.enable = true;

      extraConfig.pipewire."99-anka-latency" = {
        "context.properties" = {
          "default.clock.rate"        = 48000;
          "default.clock.quantum"     = 256;
          "default.clock.min-quantum" = 32;
          "default.clock.max-quantum" = 8192;
        };
      };
    };

    # ── Fonts ─────────────────────────────────────────────────────────────
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans      # CJK (Chinese/Japanese/Korean)
        noto-fonts-color-emoji
        liberation_ttf           # free MS font substitutes
        nerd-fonts.jetbrains-mono
        nerd-fonts.fira-code
      ];
      fontconfig = {
        defaultFonts = {
          serif      = [ "Noto Serif" "Liberation Serif" ];
          sansSerif  = [ "Noto Sans" "Liberation Sans" ];
          monospace  = [ "JetBrainsMonoNL Nerd Font" "Noto Sans Mono" ];
          emoji      = [ "Noto Color Emoji" ];
        };
        antialias = true;
        hinting.enable = true;
        subpixel.rgba  = "rgb";
      };
    };

    # ── Desktop packages ──────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      # KDE core extras
      kdePackages.dolphin
      kdePackages.konsole
      kdePackages.kate
      kdePackages.gwenview
      kdePackages.okular
      kdePackages.spectacle       # screenshot
      kdePackages.ark             # archive manager
      kdePackages.kcalc
      kdePackages.kwalletmanager
      kdePackages.plasma-systemmonitor

      # Themes / icons
      kdePackages.breeze-icons
      papirus-icon-theme

      # Wayland utilities
      wl-clipboard
      xdg-utils
      xdg-user-dirs
      qt6.qtwayland

      # Misc desktop
      firefox
      libreoffice-qt6-fresh
    ];

    # ── Qt / GTK Wayland environment ──────────────────────────────────────
    environment.variables = {
      NIXOS_OZONE_WL       = "1";     # Electron apps use Wayland
      QT_QPA_PLATFORM      = lib.mkIf cfg.wayland "wayland;xcb";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = lib.mkIf cfg.wayland "1";
      GDK_BACKEND          = lib.mkIf cfg.wayland "wayland,x11";
      MOZ_ENABLE_WAYLAND   = lib.mkIf cfg.wayland "1";
      SDL_VIDEODRIVER      = lib.mkIf cfg.wayland "wayland";
      CLUTTER_BACKEND      = lib.mkIf cfg.wayland "wayland";
    };

    # ── Locale & timezone (defaults, override per-host) ───────────────────
    time.timeZone        = lib.mkDefault "Europe/Istanbul";
    i18n.defaultLocale   = lib.mkDefault "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_TIME     = lib.mkDefault "tr_TR.UTF-8";
      LC_MONETARY = lib.mkDefault "tr_TR.UTF-8";
    };

    # ── Console keymap ────────────────────────────────────────────────────
    console.keyMap = lib.mkDefault "trq";

    # ── D-Bus (required by KDE) ───────────────────────────────────────────
    services.dbus.enable = true;
  };
}