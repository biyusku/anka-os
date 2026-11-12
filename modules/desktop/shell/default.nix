# ANKA Shell — ANKA's own desktop: Hyprland (compositor) + Quickshell (QML
# top bar, dock, panels). Opt-in and installed next to Plasma: pick "ANKA"
# on the login screen. Target: macOS-level polish in ~half of Plasma's RAM.
#
#   /etc/anka/hypr/hyprland.conf   ANKA defaults; ~/.config/hypr/hyprland.conf
#                                  sources it and holds the user's own settings
#   /etc/anka/hypr/hypridle.conf   dim, lock and screen-off timers
#   /etc/anka/hypr/hyprlock.conf   lock screen
#   qml/                           the shell (shell.qml is the entry point)
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.desktop.shell;

  wallpaper =
    if config.system.build ? ankaArtwork
    then "${config.system.build.ankaArtwork}/share/wallpapers/ANKA/contents/images/3840x2160.png"
    else "";

  shellQml = pkgs.runCommand "anka-shell-qml" { } ''
    mkdir -p $out
    cp ${./qml}/*.qml ${./qml}/*.js $out/
    cp ${../../branding/artwork/logo.svg} $out/logo.svg
  '';

  # Volume and brightness keys; also used by the shell's sliders later.
  ankaMedia = pkgs.writeShellApplication {
    name = "anka-media";
    runtimeInputs = with pkgs; [ wireplumber brightnessctl ];
    text = ''
      case "''${1:-}" in
        volume-up)       wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ ;;
        volume-down)     wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
        mute)            wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
        mic-mute)        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
        brightness-up)   brightnessctl -q set 5%+ ;;
        brightness-down) brightnessctl -q set 5%- ;;
        *) echo "usage: anka-media volume-up|volume-down|mute|mic-mute|brightness-up|brightness-down" >&2; exit 1 ;;
      esac
    '';
  };

  hyprlandConf = pkgs.replaceVars ./hyprland.conf {
    quickshell = lib.getExe pkgs.quickshell;
    shell      = "${shellQml}/shell.qml";
    media      = lib.getExe ankaMedia;
    hypridle   = lib.getExe pkgs.hypridle;
    hyprlock   = lib.getExe pkgs.hyprlock;
    launcher   = lib.getExe pkgs.fuzzel;
    inherit wallpaper;
    kbLayout   = config.services.xserver.xkb.layout;
    kbVariant  = config.services.xserver.xkb.variant;
  };

  hypridleConf = pkgs.replaceVars ./hypridle.conf {
    hyprlock = lib.getExe pkgs.hyprlock;
  };

  hyprlockConf = pkgs.replaceVars ./hyprlock.conf {
    # hyprlock's "screenshot" blurs the desktop when there is no ANKA wallpaper
    lockBackground = if wallpaper == "" then "screenshot" else wallpaper;
  };

  # First login: give the user a hyprland.conf that sources ANKA's, so
  # Hyprland never writes its own example config and updates keep applying.
  ankaSession = pkgs.writeShellScriptBin "anka-session" ''
    conf="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf"
    if [ ! -e "$conf" ]; then
      mkdir -p "$(dirname "$conf")"
      cat > "$conf" <<'EOF'
    # ANKA defaults (updated with ANKA). Add your own settings below.
    source = /etc/anka/hypr/hyprland.conf
    EOF
    fi
    exec start-hyprland
  '';

  sessionPackage = (pkgs.writeTextDir "share/wayland-sessions/anka.desktop" ''
    [Desktop Entry]
    Name=ANKA
    Comment=ANKA Shell (Hyprland)
    Exec=${ankaSession}/bin/anka-session
    Type=Application
    DesktopNames=Hyprland
  '').overrideAttrs (old: {
    passthru = (old.passthru or { }) // { providedSessions = [ "anka" ]; };
  });
in
{
  options.anka.desktop.shell = {
    enable = lib.mkEnableOption "ANKA Shell (Hyprland + Quickshell) as a login session next to Plasma";

    default = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Make ANKA Shell the default session on the login screen.";
    };
  };

  config = lib.mkIf (config.anka.desktop.enable && cfg.enable) {
    programs.hyprland.enable = true;

    services.displayManager.sessionPackages = [ sessionPackage ];
    services.displayManager.defaultSession = lib.mkIf cfg.default (lib.mkOverride 90 "anka");

    environment.etc = {
      "anka/hypr/hyprland.conf".source = hyprlandConf;
      "anka/hypr/hypridle.conf".source = hypridleConf;
      "anka/hypr/hyprlock.conf".source = hyprlockConf;
    };

    environment.systemPackages = [
      pkgs.quickshell
      pkgs.hyprlock
      pkgs.hypridle
      pkgs.hyprpolkitagent
      pkgs.fuzzel           # app launcher until the ANKA one exists
      ankaMedia
    ];

    # hyprlock checks the password through PAM.
    security.pam.services.hyprlock = { };

    # Built by `nix flake check`: replaceVars fails on a missing @variable@.
    system.build.ankaShell = pkgs.linkFarm "anka-shell" [
      { name = "qml";           path = shellQml; }
      { name = "hyprland.conf"; path = hyprlandConf; }
      { name = "hypridle.conf"; path = hypridleConf; }
      { name = "hyprlock.conf"; path = hyprlockConf; }
      { name = "session";       path = sessionPackage; }
    ];
  };
}
