# ANKA OS — look and identity
#
# One quiet, consistent look from power-on to desktop:
#   boot menu   black, ANKA logo, short list (hidden unless asked for)
#   boot splash ANKA logo and a thin progress bar on black (Plymouth)
#   login       ANKA wallpaper, Inter
#   start-up    the same logo and bar (ksplash)
#   desktop     slim top bar + floating dock, ANKA colours (graphite + red),
#               Inter, window buttons on the right only
# Sources: ./artwork (SVG, rendered at build time), ./colors.nix,
# ./look-and-feel (Plasma layout and splash), ./plymouth, ./grub.
{ config, options, lib, pkgs, ... }:

let
  cfg = config.anka.branding;
  colors = import ./colors.nix;
  # Section names like "Colors:Header][Inactive" are written as they are.
  toINI = lib.generators.toINI { mkSectionName = lib.id; };
  highContrast = config.anka.accessibility.highContrast or false;

  # Qt font strings: family,size,-1,5,weight,…
  font = size: weight: "Inter,${toString size},-1,5,${toString weight},0,0,0,0,0,0,0,0,0,0,1";

  colorScheme = pkgs.writeText "ANKA.colors" (toINI colors.scheme);

  # What a fresh user gets (their own settings still win).
  kdeglobals = colors.scheme // {
    General = removeAttrs colors.scheme.General [ "Name" ] // {
      AccentColor = colors.accent;
      font = font 10 400;
      menuFont = font 10 400;
      toolBarFont = font 10 400;
      smallestReadableFont = font 8 400;
      fixed = "Monospace,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1";
    };
    KDE = {
      LookAndFeelPackage = "org.anka.desktop";
      widgetStyle = "Breeze";
      contrast = if highContrast then 10 else 4;
    };
    Icons.Theme = "breeze-dark";
    WM = colors.scheme.WM // { activeFont = font 10 600; };
  };

  # Window buttons: minimise, maximise, close — on the right, nothing on the left.
  kwinrc = {
    "org.kde.kdecoration2" = {
      library = "org.kde.breeze";
      theme = "Breeze";
      ButtonsOnLeft = "";
      ButtonsOnRight = "IAX";
    };
  };

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
    # Icon names "anka", "anka-symbolic" (top bar) and "anka-ai" (assistant)
    install -Dm644 ${./artwork/logo.svg} $out/share/icons/hicolor/scalable/apps/anka.svg
    install -Dm644 ${./artwork/logo-symbolic.svg} $out/share/icons/hicolor/scalable/apps/anka-symbolic.svg
    install -Dm644 ${./artwork/ai.svg} $out/share/icons/hicolor/scalable/apps/anka-ai.svg

    # ── Colour scheme (System Settings › Colours) ───────────────────────
    install -Dm644 ${colorScheme} $out/share/color-schemes/ANKA.colors

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

    # ── Global theme "ANKA" (System Settings › Global Theme) ────────────
    # Breeze Dark's logout screen etc., ANKA's layout, splash and defaults.
    lnf=$out/share/plasma/look-and-feel/org.anka.desktop
    mkdir -p $lnf
    cp -r $breezeDark/contents $lnf/
    chmod -R u+w $lnf
    cp -r ${./look-and-feel/contents}/. $lnf/contents/
    chmod -R u+w $lnf
    install -Dm644 ${./artwork/logo.svg} $lnf/contents/splash/images/anka.svg
    cat > $lnf/metadata.json <<'JSON'
    {
      "KPackageStructure": "Plasma/LookAndFeel",
      "KPlugin": {
        "Id": "org.anka.desktop",
        "Name": "ANKA",
        "Description": "ANKA OS: top bar and dock, graphite and red, Inter",
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
    ColorScheme=ANKA
    AccentColor=${colors.accent}

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
    ButtonsOnLeft=
    ButtonsOnRight=IAX

    [ksplashrc][KSplash]
    Engine=KSplashQML
    Theme=org.anka.desktop
    INI
    cp $wp/contents/images/1920x1080.png $lnf/contents/previews/fullscreenpreview.jpg
    rsvg-convert -w 512 -h 288 ${./artwork/wallpaper.svg} -o $lnf/contents/previews/preview.png
  '';

  wallpaper = "${artwork}/share/wallpapers/ANKA/contents/images/3840x2160.png";

  # Boot splash: the logo and a progress bar (two-step, images from "spinner").
  plymouthTheme = pkgs.runCommand "anka-plymouth-theme" {
    nativeBuildInputs = [ pkgs.librsvg ];
  } ''
    theme=$out/share/plymouth/themes/anka
    mkdir -p $theme
    spinner=${config.boot.plymouth.package}/share/plymouth/themes/spinner
    cp $spinner/*.png $theme/
    rsvg-convert -w 128 -h 128 ${./artwork/logo.svg} -o $theme/watermark.png
    substitute ${./plymouth/anka.plymouth} $theme/anka.plymouth --subst-var out
  '';

  # Boot menu (live USB, and GRUB installs): fonts from Inter, logo, one
  # dark bar behind the selected entry.
  grubTheme = pkgs.runCommand "anka-grub-theme" {
    nativeBuildInputs = [ pkgs.grub2 pkgs.librsvg ];
  } ''
    mkdir -p $out
    cp ${./grub/theme.txt} $out/theme.txt
    rsvg-convert -w 96 -h 96 ${./artwork/logo.svg} -o $out/logo.png
    echo '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8" fill="#2c2c2e"/></svg>' > select.svg
    rsvg-convert select.svg -o $out/select_c.png
    for size in 16 20; do
      grub-mkfont --name=ANKA --size=$size --output=$out/anka-$size.pf2 \
        ${pkgs.inter}/share/fonts/truetype/InterVariable.ttf
    done
  '';

  # Live USB, legacy BIOS (syslinux): black, logo on top.
  biosSplash = pkgs.runCommand "anka-bios-splash.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
    # librsvg only loads images next to the SVG
    cp ${./artwork/logo.svg} logo.svg
    cat > splash.svg <<'SVG'
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="800" height="600">
      <rect width="800" height="600" fill="#000"/>
      <image x="352" y="72" width="96" height="96" xlink:href="logo.svg"/>
    </svg>
    SVG
    rsvg-convert splash.svg -o $out
  '';
  blackPng = pkgs.runCommand "anka-black.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
    echo '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" fill="#000"/></svg>' > black.svg
    rsvg-convert black.svg -o $out
  '';

  # Merged into the Breeze SDDM theme directory by system-path.
  sddmBackground = pkgs.writeTextDir "share/sddm/themes/breeze/theme.conf.user" ''
    [General]
    background=${wallpaper}
  '';
in
{
  options.anka.branding = {
    enable = lib.mkEnableOption "the ANKA look (logo, wallpaper, colours, Inter, boot splash)" // { default = true; };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [ artwork sddmBackground ];

      # "ANKA OS" in os-release and boot menu entries.
      # (distroId stays "nixos": tools check it.)
      system.nixos.distroName = "ANKA OS";

      # ── Type: Inter for the interface, Noto for everything Inter lacks ──
      fonts.packages = [ pkgs.inter ];
      fonts.fontconfig.defaultFonts.sansSerif = lib.mkBefore [ "Inter" ];

      # ── Desktop defaults for every user ────────────────────────────────
      environment.etc."xdg/kdeglobals".text = toINI kdeglobals;
      environment.etc."xdg/kwinrc".text = toINI kwinrc;
      environment.etc."xdg/ksplashrc".text = toINI {
        KSplash = { Engine = "KSplashQML"; Theme = "org.anka.desktop"; };
      };
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

      # ── Login screen: wallpaper (theme.conf.user above), Inter ────────
      services.displayManager.sddm.settings.Theme.Font = "Inter,10";

      # ── Boot splash ────────────────────────────────────────────────────
      boot.plymouth = {
        theme = "anka";
        themePackages = [ plymouthTheme ];
        font = "${pkgs.inter}/share/fonts/truetype/InterVariable.ttf";
        logo = "${artwork}/share/anka/logo-128.png";
      };

      # ── Boot menu (GRUB installs; systemd-boot draws no theme) ────────
      boot.loader.grub = {
        theme = grubTheme;
        splashImage = null;
      };

      # Built by `nix flake check` (see checks in flake.nix)
      system.build.ankaArtwork = artwork;
      system.build.ankaBootArtwork = pkgs.linkFarm "anka-boot-artwork" [
        { name = "plymouth"; path = plymouthTheme; }
        { name = "grub"; path = grubTheme; }
        { name = "bios-splash.png"; path = biosSplash; }
      ];
    }

    # ── Live USB boot menu ───────────────────────────────────────────────
    (lib.optionalAttrs (options ? isoImage) {
      isoImage = {
        grubTheme = grubTheme;
        efiSplashImage = blackPng;
        splashImage = biosSplash;
        syslinuxTheme = ''
          MENU TITLE ANKA OS
          MENU RESOLUTION 800 600
          MENU CLEAR
          MENU ROWS 6
          MENU VSHIFT 10
          MENU CMDLINEROW -4
          MENU TIMEOUTROW -3
          MENU TABMSGROW  -2
          MENU HELPMSGROW -1
          MENU HELPMSGENDROW -1
          MENU MARGIN 16

          #                                FG:AARRGGBB  BG:AARRGGBB   shadow
          MENU COLOR BORDER       30;44      #00000000    #00000000   none
          MENU COLOR SCREEN       37;40      #FF000000    #00000000   none
          MENU COLOR TABMSG       31;40      #FF555555    #00000000   none
          MENU COLOR TIMEOUT      1;37;40    #FF555555    #00000000   none
          MENU COLOR TIMEOUT_MSG  37;40      #FF555555    #00000000   none
          MENU COLOR CMDMARK      1;36;40    #FF98989D    #00000000   none
          MENU COLOR CMDLINE      37;40      #FFF5F5F7    #00000000   none
          MENU COLOR TITLE        1;36;44    #00000000    #00000000   none
          MENU COLOR UNSEL        37;44      #FF98989D    #00000000   none
          MENU COLOR SEL          7;37;40    #FFF5F5F7    #FF2C2C2E   none
        '';
      };
    })
  ]);
}
