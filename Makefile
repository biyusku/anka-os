# Kiwimi OS — Build System
# Usage: make <target>

.PHONY: build-iso test-iso rebuild update gc check fmt help

# ── ISO ───────────────────────────────────────────────────────────────────────
## Build the live installer ISO
build-iso:
	nix build .#packages.x86_64-linux.iso --out-link result-iso
	@echo ""
	@echo "ISO built: $$(readlink result-iso)/iso/kiwimi.iso"

## Test the ISO in QEMU (requires KVM + 4 GB RAM)
test-iso: result-iso
	qemu-system-x86_64 \
	  -enable-kvm \
	  -m 4G \
	  -smp 2 \
	  -cpu host \
	  -vga virtio \
	  -display gtk,gl=on \
	  -device virtio-net-pci,netdev=net0 \
	  -netdev user,id=net0 \
	  -cdrom result-iso/iso/kiwimi.iso \
	  -boot d \
	  -bios /run/current-system/firmware/bios.bin 2>/dev/null || \
	qemu-system-x86_64 \
	  -enable-kvm \
	  -m 4G \
	  -smp 2 \
	  -cdrom result-iso/iso/kiwimi.iso \
	  -boot d

## Test the ISO with UEFI firmware (ovmf)
test-iso-uefi: result-iso
	qemu-system-x86_64 \
	  -enable-kvm \
	  -m 4G \
	  -smp 2 \
	  -cpu host \
	  -bios $$(nix-build '<nixpkgs>' -A OVMF.fd --no-out-link)/FV/OVMF.fd \
	  -cdrom result-iso/iso/kiwimi.iso \
	  -boot d

# ── System rebuild ────────────────────────────────────────────────────────────
## Rebuild and switch to the new configuration on the current machine
rebuild:
	sudo nixos-rebuild switch --flake .#kiwimi

## Rebuild and boot into the new generation on next reboot
rebuild-boot:
	sudo nixos-rebuild boot --flake .#kiwimi

## Test build without switching (dry-run)
rebuild-dry:
	nixos-rebuild dry-build --flake .#kiwimi

# ── Flake maintenance ─────────────────────────────────────────────────────────
## Update all flake inputs to their latest commits
update:
	nix flake update

## Update a specific flake input (usage: make update-input INPUT=nixpkgs)
update-input:
	nix flake update $(INPUT)

## Show current flake input revisions
show-inputs:
	nix flake metadata

# ── Store maintenance ─────────────────────────────────────────────────────────
## Garbage-collect store paths not referenced by any GC root
gc:
	nix store gc --delete-older-than 30d
	@echo "Store garbage collection complete."

## Show disk usage of the Nix store
store-size:
	du -sh /nix/store

## Optimise the store (deduplication via hard-linking)
store-optimize:
	nix store optimise

# ── Code quality ──────────────────────────────────────────────────────────────
## Check that all .nix files parse (no evaluation, just syntax)
check:
	@echo "Checking flake..."
	nix flake check --no-build
	@echo "All checks passed."

## Format all .nix files with nixfmt (if installed)
fmt:
	@if command -v nixfmt >/dev/null 2>&1; then \
	  find . -name '*.nix' -not -path '*/result*' -exec nixfmt {} +; \
	  echo "Formatting done."; \
	else \
	  echo "nixfmt not found — install with: nix-env -iA nixpkgs.nixfmt"; \
	fi

# ── Help ──────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  Kiwimi OS Build System"
	@echo "  ══════════════════════"
	@echo ""
	@echo "  ISO"
	@echo "    make build-iso       Build the live installer ISO"
	@echo "    make test-iso        Test ISO in QEMU (BIOS)"
	@echo "    make test-iso-uefi   Test ISO in QEMU (UEFI/OVMF)"
	@echo ""
	@echo "  System"
	@echo "    make rebuild         nixos-rebuild switch (current machine)"
	@echo "    make rebuild-boot    nixos-rebuild boot (next reboot)"
	@echo "    make rebuild-dry     Dry-run build, no switch"
	@echo ""
	@echo "  Flake"
	@echo "    make update          Update all flake inputs"
	@echo "    make update-input INPUT=<name>"
	@echo "                         Update a single flake input"
	@echo "    make show-inputs     Show current input revisions"
	@echo ""
	@echo "  Store"
	@echo "    make gc              Delete store paths older than 30 days"
	@echo "    make store-size      Show /nix/store disk usage"
	@echo "    make store-optimize  Deduplication (hard-links)"
	@echo ""
	@echo "  Quality"
	@echo "    make check           Syntax-check all .nix files"
	@echo "    make fmt             Format .nix files with nixfmt"
	@echo ""
