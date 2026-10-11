# ANKA OS — Live ISO configuration
# Build: nix build .#packages.x86_64-linux.iso
# `gpu` comes from specialArgs in flake.nix ("amd" | "nvidia" | "intel").
{ config, lib, pkgs, modulesPath, inputs, gpu, ... }:

{
  imports = [
    # Graphical live system (no installer: nixpkgs' Calamares installs plain
    # NixOS, ANKA brings its own below)
    "${modulesPath}/installer/cd-dvd/installation-cd-graphical-base.nix"

    # The ANKA installer
    ./calamares

    # ANKA look in the live session (wallpaper, boot splash logo)
    ../modules/branding/default.nix

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

  # ── GPU driver variant for this ISO ───────────────────────────────────────
  anka.gpu.type = gpu;

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
    # New default from NixOS 26.11; safer for pools imported on a live system
    zfs.forceImportRoot = false;
  };

  # ── Display & Wayland ──────────────────────────────────────────────────────
  services.displayManager = {
    sddm = {
      enable    = true;
      wayland.enable = true;
    };
    autoLogin = {
      enable = lib.mkForce true;
      user   = lib.mkForce "anka";
    };
    defaultSession = "plasma";
  };

  services.desktopManager.plasma6 = {
    enable = true;
    enableQt5Integration = false;
  };
  # Optional wallpapers add ~126 MiB to the ISO
  environment.plasma6.excludePackages = [ pkgs.kdePackages.plasma-workspace-wallpapers ];
  # Avoid bundling an entire MariaDB installation on the ISO
  programs.kde-pim.enable = false;
  isoImage.edition = lib.mkDefault "plasma6";

  # Force Wayland for KDE
  environment.sessionVariables = {
    NIXOS_OZONE_WL       = "1";
    XDG_SESSION_TYPE     = "wayland";
    QT_QPA_PLATFORM      = "wayland";
    SDL_VIDEODRIVER      = "wayland,x11";
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
    wireless.enable       = lib.mkForce false; # NM handles Wi-Fi
    hostName              = lib.mkForce "anka-live";
  };

  # ── ISO image settings ─────────────────────────────────────────────────────
  image.fileName = "anka-${gpu}.iso";

  isoImage = {
    volumeID            = "anka-OS";
    squashfsCompression = "zstd -Xcompression-level 19";
    # Sticker for the ISO menu
    appendToMenuLabel = " ANKA OS Live";
  };

  # ── Desktop shortcut for the installer ────────────────────────────────────
  systemd.tmpfiles.settings."10-anka-installer-desktop" = {
    "/home/anka/Desktop".d = {
      user  = "anka";
      group = "users";
      mode  = "0755";
    };
    "/home/anka/Desktop/install-anka.desktop"."L+".argument =
      "/run/current-system/sw/share/applications/calamares.desktop";
  };

  # ── Packages available in the live environment ────────────────────────────
  environment.systemPackages = with pkgs; [
    # Essential tools
    git
    wget
    curl
    htop
    fastfetch
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
    pulseaudio.enable = false; # using pipewire
    pipewire = {
      enable            = true;
      alsa.enable       = true;
      alsa.support32Bit = true;
      pulse.enable      = true;
    };
  };

  hardware = {
    bluetooth.enable     = true;
    graphics.enable      = true;
  };

  # ── System label ──────────────────────────────────────────────────────────
  system.stateVersion = "25.11";
}