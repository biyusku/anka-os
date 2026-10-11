# ANKA OS — look and identity
#
# One look from boot to desktop: the ANKA logo and name on the boot splash,
# the ANKA wallpaper on the login screen, desktop and lock screen, Breeze
# Dark with ANKA's red accent, and the logo in System Settings › About.
# Artwork sources: ./artwork (SVG, rendered to PNG at build time).
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.branding;

  accent = "192,57,43";   # #c0392b, docs/branding.md

  artwork = pkgs.runCommand "anka-artwork" {
    nativeBuildInputs = [ pkgs.librsvg ];
    breezeDark = "${pkgs.kdePackages.plasma-workspace}/share/plasma/look-and-feel/org.kde.breezedark.desktop";
  } ''
    # ── Logo ────────────────────────────────────────────────────────────
    mkdir -p $out/share/anka
    cp ${./artwork/logo.svg} $out/share/anka/logo.svg
    for size in 48 128 256; do
      rsvg-convert -w $size -h $size ${./artwork/logo.svg} -o $out/share/anka/logo-$size.png
    done
    # Icon name "anka" (KRunner, launchers)
    install -Dm644 ${./artwork/logo.svg} $out/share/icons/hicolor/scalable/apps/anka.svg

    # ── Wallpaper (Plasma wallpaper package "ANKA") ─────────────────────
    wp=$out/share/wallpapers/ANKA
    mkdir -p $wp/contents/images
    for res in 3840x2160 2560x1440 1920x1080 1366x768; do
      rsvg-convert -w ''${res%x*} -h ''${res#*x} ${./artwork/wallpaper.svg} -o $wp/contents/images/$res.png
    done
    rsvg-convert -w 400 -h 225 ${./artwork/wallpaper.svg} -o $wp/contents/screenshot.png
    cat > $wp/metadata.json <<'JSON'
    {
      "KPlugin": {
        "Id": "ANKA",
        "Name": "ANKA",
        "Authors": [ { "Name": "ANKA OS" } ],
        "License": "CC-BY-SA-4.0"
      }
    }
    JSON

    # ── Look and Feel "ANKA": Breeze Dark's layout + ANKA defaults ──────
    lnf=$out/share/plasma/look-and-feel/org.anka.desktop
    mkdir -p $lnf
    cp -r $breezeDark/contents $lnf/
    chmod -R u+w $lnf
    cat > $lnf/metadata.json <<'JSON'
    {
      "KPackageStructure": "Plasma/LookAndFeel",
      "KPlugin": {
        "Id": "org.anka.desktop",
        "Name": "ANKA",
        "Description": "ANKA OS: Breeze Dark with ANKA's accent and wallpaper",
        "Authors": [ { "Name": "ANKA OS" } ],
        "License": "GPLv2+",
        "Website": "https://github.com/biyusku/anka-os"
      }
    }
    JSON
    cat > $lnf/contents/defaults <<'INI'
    [kdeglobals][KDE]
    widgetStyle=Breeze

    [kdeglobals][General]
    ColorScheme=BreezeDark
    AccentColor=${accent}

    [kdeglobals][Icons]
    Theme=breeze-dark

    [plasmarc][Theme]
    name=default

    [Wallpaper]
    Image=ANKA

    [kcminputrc][Mouse]
    cursorTheme=breeze_cursors

    [kwinrc][org.kde.kdecoration2]
    library=org.kde.breeze
    theme=Breeze

    [ksplashrc][KSplash]
    Theme=org.kde.breeze.desktop
    INI
    cp $wp/contents/images/1920x1080.png $lnf/contents/previews/fullscreenpreview.jpg
    rsvg-convert -w 512 -h 288 ${./artwork/wallpaper.svg} -o $lnf/contents/previews/preview.png
  '';

  wallpaper = "${artwork}/share/wallpapers/ANKA/contents/images/3840x2160.png";

  # Merged into the Breeze SDDM theme directory by system-path.
  sddmBackground = pkgs.writeTextDir "share/sddm/themes/breeze/theme.conf.user" ''
    [General]
    background=${wallpaper}
  '';
in
{
  options.anka.branding = {
    enable = lib.mkEnableOption "the ANKA look (logo, wallpaper, accent colour)" // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ artwork sddmBackground ];

    # "ANKA OS" in os-release, boot menu entries and the boot splash.
    # (distroId stays "nixos": tools check it.)
    system.nixos.distroName = "ANKA OS";
    boot.plymouth.logo = "${artwork}/share/anka/logo-128.png";

    # Defaults for every user (their own settings still win).
    environment.etc."xdg/kdeglobals".text = ''
      [KDE]
      LookAndFeelPackage=org.anka.desktop

      [General]
      ColorScheme=BreezeDark
      AccentColor=${accent}

      [Icons]
      Theme=breeze-dark
    '';

    environment.etc."xdg/kscreenlockerrc".text = ''
      [Greeter][Wallpaper][org.kde.image][General]
      Image=file://${wallpaper}
      PreviewImage=file://${wallpaper}
    '';

    # System Settings › About this System
    environment.etc."xdg/kcm-about-distrorc".text = ''
      [General]
      LogoPath=${artwork}/share/anka/logo.svg
      Website=https://github.com/biyusku/anka-os
    '';

    # Built by `nix flake check` (see checks in flake.nix)
    system.build.ankaArtwork = artwork;
  };
}
