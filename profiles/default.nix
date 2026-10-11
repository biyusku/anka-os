# ANKA OS — the settings ANKA ships with.
# Every value is a default (lib.mkDefault), so a machine's own
# configuration.nix can override any of them without conflicts.
{ lib, ... }:

{
  # anka.profile = "light" trims the extras (see light.nix).
  imports = [ ./light.nix ];

  # Firmware for GPUs, Wi-Fi/Bluetooth chips and CPU microcode updates.
  # Off by default on NixOS; without it AMD graphics and most wireless
  # cards don't work.
  hardware.enableAllFirmware = lib.mkDefault true;

  anka = lib.mapAttrsRecursive (_: lib.mkDefault) {
    # ── Boot & kernel ─────────────────────────────────────────────────────
    boot = {
      loader   = "systemd-boot";
      plymouth = true;
      timeout  = 3;
    };
    kernel.variant = "linux_zen";   # prebuilt; CachyOS compiles on the machine

    # ── Filesystem ────────────────────────────────────────────────────────
    filesystem = {
      rootFormat      = "btrfs";
      btrfsSubvolumes = true;
      tmpOnTmpfs      = true;
    };

    # ── Network ───────────────────────────────────────────────────────────
    network = {
      hostname  = "anka";
      manager   = "networkmanager";
      mdns      = true;
      bluetooth = true;
    };

    # ── Security ──────────────────────────────────────────────────────────
    security = {
      enable = true;
      firewall = {
        enable   = true;
        allowSsh = false;      # no SSH by default on a desktop
      };
      apparmor.enable = true;
      fail2ban.enable = false; # only needed when SSH is open
      kernelHardening = true;
    };

    # ── Desktop ───────────────────────────────────────────────────────────
    desktop = {
      enable           = true;
      session          = "plasma6";
      wayland          = true;
      autoLogin.enable = false;
      extraApps        = true;
    };

    # ── GPU (the installer detects and overrides this) ────────────────────
    gpu.type = "amd";

    # ── Gaming ────────────────────────────────────────────────────────────
    gaming = {
      enable           = true;
      steam.enable     = true;
      gamescope.enable = true;
      lutris           = true;
      heroic           = true;
      discord          = true;
    };

    # ── Applications ──────────────────────────────────────────────────────
    apps = {
      enable   = true;
      flatpak  = true;
      terminal = "konsole";
      browser  = "firefox";
    };

    # ── AI layer ──────────────────────────────────────────────────────────
    ai = {
      enable       = true;
      localModel   = "qwen2.5:7b";
      enableVoice  = true;
      whisperModel = "base";
      mcp.enable   = true;
    };

    # ── Performance ───────────────────────────────────────────────────────
    performance = {
      enable = true;
      zram = {
        enable        = true;
        algorithm     = "lz4";
        memoryPercent = 50;
      };
      scheduler      = "scx_lavd";  # Valve's Steam Deck scheduler
      governor       = "schedutil";
      thp            = "madvise";
      enableEarlyoom = true;
      gaming = {
        enable        = true;
        realtimeAudio = true;
        amdTweaks     = true;
      };
    };

    # ── Windows compatibility ─────────────────────────────────────────────
    compat.windows = {
      enable           = true;
      geProton.enable  = true;
      umuLauncher      = true;
      protontricks     = true;
      bottles          = true;
      ntfs = {
        enable = true;
        driver = "ntfs-3g";
      };
    };

    # ── Media codecs ──────────────────────────────────────────────────────
    compat.media = {
      enable         = true;
      dvd            = true;
      hardwareDecode = true;
      vaapi          = true;
      extraPlayers   = true;
    };

    # ── Opt-in layers ─────────────────────────────────────────────────────
    accessibility.enable = false;
    adobe.enable         = false;

    # ── Updates & first-run wizard ────────────────────────────────────────
    update = {
      enable    = true;
      channel   = "stable";
      autoApply = false;   # notify-only; the user updates from the KCM
    };
    installer.enable = true;
  };
}
