# ANKA Accessibility — Orca screen reader, AT-SPI2, KDE a11y, large fonts
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.accessibility;
in
{
  options.anka.accessibility = {
    enable = lib.mkEnableOption "ANKA accessibility features (Orca, AT-SPI2, KDE a11y)";

    orca = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Install and enable Orca screen reader (GNOME/AT-SPI2 based).";
    };

    atSpi = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = ''
        Enable AT-SPI2 accessibility bus.
        Required by Orca and also used by the ANKA AI daemon for UI automation.
      '';
    };

    largeFonts = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = "Set system-wide DPI to 120 (1.25× scale) for better readability.";
    };

    dpi = lib.mkOption {
      type    = lib.types.ints.between 72 288;
      default = 120;
      description = ''
        X11/Wayland DPI when largeFonts is true.
        96 = 100 % (default), 120 = 125 %, 144 = 150 %, 192 = 200 %.
      '';
    };

    highContrast = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = "Install high-contrast KDE/GTK themes.";
    };

    brailleDisplay = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = "Install BrlTTY for Braille display support.";
    };

    onScreenKeyboard = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = "Install Maliit keyboard (Wayland on-screen keyboard for KDE Plasma).";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── AT-SPI2 accessibility bus ─────────────────────────────────────────────
    services.gnome.at-spi2-core.enable = lib.mkIf cfg.atSpi true;

    # DBus activation for AT-SPI2 (needed even without full GNOME)
    services.dbus.enable = true;

    # ── Orca ─────────────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; lib.concatLists [
      (lib.optional cfg.orca            orca)
      (lib.optional cfg.orca            espeak-ng)           # default TTS backend for Orca
      (lib.optional cfg.brailleDisplay  brltty)
      (lib.optional cfg.onScreenKeyboard maliit-keyboard)
      (lib.optional cfg.highContrast    hicolor-icon-theme)
    ];

    # ── speech-dispatcher (Orca TTS backend) ─────────────────────────────────
    services.speechd = {
      enable = lib.mkIf cfg.orca true;
    };

    # ── BrlTTY system service ─────────────────────────────────────────────────
    services.brltty.enable = lib.mkIf cfg.brailleDisplay true;

    # ── Font DPI / scale ──────────────────────────────────────────────────────
    # Fonts in NixOS are set via fontconfig; for DPI we write an Xresources file
    # and a KDE plasma-setup script.
    environment.etc."X11/Xresources.d/anka-dpi".text = lib.mkIf cfg.largeFonts ''
      Xft.dpi: ${toString cfg.dpi}
    '';

    fonts.fontconfig = lib.mkIf cfg.largeFonts {
      # subpixel rendering for LCD screens
      subpixel.rgba = lib.mkDefault "rgb";
      antialias     = lib.mkDefault true;
      hinting.enable = lib.mkDefault true;
    };

    # ── KDE accessibility defaults ────────────────────────────────────────────
    # System-wide defaults in /etc/xdg apply to every user (their own
    # settings still win). Writing into home directories as root would
    # leave root-owned files the user can no longer change.
    environment.etc."xdg/kcmfonts".text = lib.mkIf cfg.largeFonts ''
      [General]
      forceFontDPI=${toString cfg.dpi}
    '';
    environment.etc."xdg/kdeglobals".text = lib.mkIf cfg.highContrast ''
      [KDE]
      contrast=10
    '';

    # ── GTK high-contrast theme ───────────────────────────────────────────────
    environment.etc."gtk-3.0/settings.ini".text = lib.mkIf cfg.highContrast ''
      [Settings]
      gtk-theme-name=HighContrast
      gtk-icon-theme-name=HighContrast
    '';

    # ── Kernel: accessibility drivers (braille, tactile devices) ─────────────
    boot.kernelModules = lib.mkIf cfg.brailleDisplay [ "usbhid" ];

  };
}