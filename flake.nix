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

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        chaotic.overlays.default
      ];
    };
  in
  {
    # ── Default host (generic PC install target) ──────────────────────────
    nixosConfigurations.anka = nixpkgs.lib.nixosSystem {
      inherit system pkgs;
      specialArgs = { inherit inputs; };
      modules = [
        chaotic.nixosModules.default
        disko.nixosModules.disko
        home-manager.nixosModules.home-manager
        ./hosts/default/configuration.nix
        # ── First-run wizard ─────────────────────────────────────────────────
        ./modules/installer/default.nix
        # ── Update system ────────────────────────────────────────────────────
        ./modules/update/default.nix
        ./modules/update/version.nix
      ];
    };

    # ── Installer ISOs ────────────────────────────────────────────────────
    # Base ISO (generic / AMD GPU)
    # Build with: nix build .#packages.x86_64-linux.iso-amd
    nixosConfigurations.anka-iso = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
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