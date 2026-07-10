# ANKA OS — Live ISO configuration
# Build: nix build .#packages.x86_64-linux.iso
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Graphical Calamares installer with KDE Plasma 6
    "${toString <nixpkgs>}/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix"

    # Bring in ANKA system modules (subset safe for ISO)
    ../modules/desktop/default.nix
    ../modules/gpu/default.nix
    ../modules/compat/media.nix
    ../modules/accessibility/default.nix
  ];

  # ── Nix settings ──────────────────────────────────────────────────────────
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # Binary caches for faster installs
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://chaotic-nyx.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dode3561l0bLr/hZfuLvXFp4sDV1p9u8Q="
        "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n17rIDy40agHj12WfF+Gqk6SonIT8="
      ];
    };
    # Allow unfree packages in the ISO
    package = pkgs.nix;
  };

  nixpkgs.config.allowUnfree = true;

  # ── System locale ──────────────────────────────────────────────────────────
  i18n = {
    defaultLocale = "en_US.UTF-8";
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "tr_TR.UTF-8/UTF-8"
    ];
    extraLocaleSettings = {
      LC_MONETARY = "tr_TR.UTF-8";
      LC_PAPER    = "tr_TR.UTF-8";
      LC_TIME     = "tr_TR.UTF-8";
    };
  };

  # Timezone default (user can change during install)
  time.timeZone = lib.mkDefault "Europe/Istanbul";

  # ── Console & keyboard ─────────────────────────────────────────────────────
  console = {
    font   = "Lat2-Terminus16";
    keyMap = lib.mkDefault "us";
  };

  services.xserver.xkb = {
    layout  = "us,tr";
    variant = ",";
    options = "grp:alt_shift_toggle";
  };

  # ── Boot: Plymouth splash ──────────────────────────────────────────────────
  boot = {
    plymouth = {
      enable  = true;
      theme   = "spinner";
    };
    # Quiet boot for polished UX
    kernelParams = [
      "quiet"
      "splash"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
    loader.timeout = lib.mkForce 3;
  };

  # ── Display & Wayland ──────────────────────────────────────────────────────
  services.displayManager = {
    sddm = {
      enable    = true;
      wayland.enable = true;
      autoLogin = {
        enable = true;
        user   = "anka";
      };
    };
    defaultSession = "plasma";
  };

  services.desktopManager.plasma6.enable = true;

  # Force Wayland for KDE
  environment.sessionVariables = {
    NIXOS_OZONE_WL       = "1";
    XDG_SESSION_TYPE     = "wayland";
    QT_QPA_PLATFORM      = "wayland";
    SDL_VIDEODRIVER      = "wayland";
    MOZ_ENABLE_WAYLAND   = "1";
  };

  # ── Live user: anka ──────────────────────────────────────────────────────
  users.users.anka = {
    isNormalUser    = true;
    description     = "ANKA Live User";
    password        = "";                        # passwordless
    extraGroups     = [ "wheel" "networkmanager" "audio" "video" "input" ];
    uid             = 1000;
    shell           = pkgs.bash;
  };

  # Allow sudo without password for the live session
  security.sudo = {
    enable         = true;
    wheelNeedsPassword = false;
  };

  # ── SSH: off by default ────────────────────────────────────────────────────
  services.openssh.enable = lib.mkForce false;

  # ── NetworkManager ─────────────────────────────────────────────────────────
  networking = {
    networkmanager.enable = true;
    wireless.enable       = false; # NM handles Wi-Fi
    hostName              = "anka-live";
  };

  # ── Calamares installer configuration ─────────────────────────────────────
  services.calamares = {
    branding     = "anka";
    # Point Calamares at our custom config directory
    configDir    = pkgs.runCommand "calamares-anka-config" {} ''
      cp -r ${./calamares} $out
    '';
  };

  # ── ISO image settings ─────────────────────────────────────────────────────
  isoImage = {
    volumeID            = "anka-OS";
    isoName             = "anka.iso";
    squashfsCompression = "zstd -Xcompression-level 19";
    # Include the installer configs in the ISO
    contents = [
      {
        source = ./calamares;
        target = "/etc/calamares";
      }
    ];
    # Sticker for the ISO menu
    appendToMenuLabel = " ANKA OS Live";
  };

  # ── Packages available in the live environment ────────────────────────────
  environment.systemPackages = with pkgs; [
    # Installer
    calamares-nixos
    calamares-nixos-extensions

    # Essential tools
    git
    wget
    curl
    htop
    neofetch
    gparted
    ntfs3g

    # File manager
    kdePackages.dolphin
    kdePackages.ark

    # Hardware detection
    pciutils
    usbutils
    lshw

    # Networking
    networkmanagerapplet

    # Multimedia
    vlc
    firefox

    # Text editor
    kdePackages.kate

    # Terminal
    kdePackages.konsole
  ];

  # ── System services ────────────────────────────────────────────────────────
  services = {
    # Bluetooth
    blueman.enable = true;

    # Printing (optional, nice to have)
    printing.enable = true;

    # Audio
    pipewire = {
      enable            = true;
      alsa.enable       = true;
      alsa.support32Bit = true;
      pulse.enable      = true;
    };
  };

  hardware = {
    bluetooth.enable     = true;
    pulseaudio.enable    = false; # using pipewire
    graphics.enable      = true;
  };

  # ── System label ──────────────────────────────────────────────────────────
  system.stateVersion = "25.11";
}