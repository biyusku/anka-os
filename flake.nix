# ANKA OS — NixOS flake root
# "Windows kadar destekli, Mac kadar şık, Linux kadar optimize."
{
  description = "ANKA OS — AI-native NixOS distribution for everyone";

  nixConfig = {
    extra-substituters = [
      "https://anka-os.cachix.org"
    ];
    extra-trusted-public-keys = [
      # Replace this placeholder with the real key from: cachix use anka-os
      "anka-os.cachix.org-1:u9yt44pc+SaTI7iBP2t+r0E62ECtrOx8on0Y5V8pUyM="
    ];
  };

  inputs = {
    # ── Core nixpkgs (unstable for latest packages) ───────────────────────
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # ── Home Manager (user-level dotfile management) ──────────────────────
    home-manager = {
      url   = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── Chaotic-Nyx (CachyOS kernel + extra overlays) ─────────────────────
    chaotic = {
      url   = "github:chaotic-aur/nyx/nyxpkgs-unstable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── Disko (declarative disk partitioning) ─────────────────────────────
    disko = {
      url   = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, chaotic, disko, ... } @ inputs:
  let
    system = "x86_64-linux";

    # Build an ANKA system from ANKA's modules + profile and the machine's
    # own modules (hardware-configuration.nix, configuration.nix, ...).
    mkSystem = { modules ? [ ], specialArgs ? { } }:
      nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; } // specialArgs;
        modules = [ self.nixosModules.default ] ++ modules;
      };
  in
  {
    # ── ANKA as a NixOS module ────────────────────────────────────────────
    # Everything that makes a NixOS machine an ANKA machine. Installed
    # systems use it through `lib.mkSystem` from their /etc/nixos flake.
    nixosModules.default = { lib, ... }: {
      imports = [
        chaotic.nixosModules.default   # CachyOS kernel (adds its own overlay)
        disko.nixosModules.disko
        home-manager.nixosModules.home-manager
        ./modules
        ./profiles/default.nix
      ];
      nixpkgs.hostPlatform       = lib.mkDefault system;
      nixpkgs.config.allowUnfree = lib.mkDefault true;
      # Keep the ANKA source this system was built from out of the garbage
      # collector, so `nixos-rebuild` keeps working without fetching it.
      system.extraDependencies = [ self.outPath ];
    };

    lib.mkSystem = mkSystem;

    # ── Reference host (evaluated by CI) ──────────────────────────────────
    nixosConfigurations.anka = mkSystem {
      modules = [ ./hosts/default/configuration.nix ];
    };

    # ── Installer ISOs ────────────────────────────────────────────────────
    # Base ISO (generic / AMD GPU)
    # Build with: nix build .#packages.x86_64-linux.iso-amd
    nixosConfigurations.anka-iso = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; gpu = "amd"; };
      modules = [
        chaotic.nixosModules.default
        ./iso/default.nix
      ];
    };

    # NVIDIA variant — passes gpu=nvidia into the ISO module
    nixosConfigurations.anka-iso-nvidia = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; gpu = "nvidia"; };
      modules = [
        chaotic.nixosModules.default
        ./iso/default.nix
      ];
    };

    # Intel integrated-graphics variant
    nixosConfigurations.anka-iso-intel = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; gpu = "intel"; };
      modules = [
        chaotic.nixosModules.default
        ./iso/default.nix
      ];
    };

    # ── Built by `nix flake check` (CI) ───────────────────────────────────
    # Packages ANKA builds itself: evaluating the system doesn't compile them.
    checks.${system} = {
      # Every variant must evaluate. Optional features are off by default,
      # so without this a broken one goes unnoticed until someone turns it
      # on. Only evaluated (the drv paths' context is dropped), not built.
      option-matrix =
        let
          inherit (nixpkgs) lib;
          variants = {
            light         = { anka.profile = "light"; };
            nvidia        = { anka.gpu.type = "nvidia"; anka.gpu.nvidia.open = true; };
            intel         = { anka.gpu.type = "intel"; };
            hybrid        = { anka.gpu.type = "intel+nvidia"; anka.gpu.nvidia.prime.enable = true; };
            no-gpu        = { anka.gpu.type = "none"; };
            game-mode     = { anka.gaming.gameMode.default = true;
                              anka.desktop.autoLogin = { enable = true; user = "anka"; }; };
            accessibility = { anka.accessibility = { enable = true; orca = true; largeFonts = true;
                                                     highContrast = true; brailleDisplay = true; }; };
            a11y-minimal  = { anka.accessibility.enable = true; };
            no-branding   = { anka.branding.enable = false; anka.accessibility = { enable = true; highContrast = true; }; };
            ssh           = { anka.security.firewall.allowSsh = true; anka.security.fail2ban.enable = true; };
            usbguard      = { anka.security.usbGuard.enable = true; };
            adobe         = { anka.adobe.enable = true; };
            wine-office   = { anka.compat.windows.wineOffice = true; };
            gnome         = { anka.desktop.session = "gnome"; };
            xanmod        = { anka.kernel.variant = "linux_xanmod"; };
            stock-kernel  = { anka.kernel.variant = "default"; };
            ai-cpu        = { anka.ai.acceleration = "cpu"; };
            update-auto   = { anka.update.autoApply = true; anka.update.channel = "unstable"; };
          };
          evaluate = name: module:
            builtins.unsafeDiscardStringContext
              (self.nixosConfigurations.anka.extendModules {
                modules = [ (lib.mapAttrsRecursive (_: lib.mkOverride 50) module) ];
              }).config.system.build.toplevel.drvPath;
        in
        self.nixosConfigurations.anka.pkgs.writeText "anka-option-matrix"
          (lib.concatStringsSep "\n" (lib.mapAttrsToList (n: m: "${n} ${evaluate n m}") variants));

      anka-update     = self.nixosConfigurations.anka.config.system.build.ankaUpdate;
      kcm-anka-update = self.nixosConfigurations.anka.config.system.build.kcmAnkaUpdate;
      anka-ai         = self.nixosConfigurations.anka.config.system.build.ankaAi;
      anka-mcp        = self.nixosConfigurations.anka.config.system.build.ankaMcpServers;
      anka-first-run  = self.nixosConfigurations.anka.config.system.build.ankaFirstRun;
      anka-artwork    = self.nixosConfigurations.anka.config.system.build.ankaArtwork;
    };

    # ── Convenience package aliases ───────────────────────────────────────
    # nix build .#iso            → generic / AMD
    # nix build .#iso-amd        → explicit AMD alias
    # nix build .#iso-nvidia     → NVIDIA proprietary drivers
    # nix build .#iso-intel      → Intel open-source drivers
    packages.${system} = {
      iso        = self.nixosConfigurations.anka-iso.config.system.build.isoImage;
      iso-amd    = self.nixosConfigurations.anka-iso.config.system.build.isoImage;
      iso-nvidia = self.nixosConfigurations.anka-iso-nvidia.config.system.build.isoImage;
      iso-intel  = self.nixosConfigurations.anka-iso-intel.config.system.build.isoImage;
    };
  };
}