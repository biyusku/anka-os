#!/usr/bin/env bash
# ANKA OS ISO Builder
# Builds a bootable ISO image from the ANKA NixOS configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANKA_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${ANKA_ROOT}/output"
LOG_FILE="${OUTPUT_DIR}/build-iso.log"

# Load version info
if [[ -f "${ANKA_ROOT}/VERSION" ]]; then
    source "${ANKA_ROOT}/VERSION"
fi

ANKA_VERSION="${ANKA_VERSION:-0.1.0}"
ISO_NAME="anka-os-${ANKA_VERSION}-x86_64.iso"

echo "=================================================="
echo "  ANKA OS ISO Builder"
echo "  Version: ${ANKA_VERSION}"
echo "  Output: ${OUTPUT_DIR}/${ISO_NAME}"
echo "=================================================="

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Check prerequisites
check_prerequisites() {
    echo "[*] Checking prerequisites..."

    if ! command -v nix &> /dev/null; then
        echo "[ERROR] nix is not installed or not in PATH"
        exit 1
    fi

    if ! command -v nixos-rebuild &> /dev/null; then
        echo "[ERROR] nixos-rebuild is not found"
        exit 1
    fi

    echo "[OK] Prerequisites satisfied"
}

# Build the ISO
build_iso() {
    echo "[*] Building ANKA OS ISO..."
    echo "[*] This may take 20-60 minutes depending on your system"
    echo ""

    # Build using nix
    nix build \
        --flake "${ANKA_ROOT}#packages.x86_64-linux.iso" \
        --out-link "${OUTPUT_DIR}/anka-result" \
        --log-format bar-with-logs \
        2>&1 | tee "${LOG_FILE}"

    if [[ $? -eq 0 ]]; then
        echo ""
        echo "[OK] ISO built successfully"

        # Copy ISO to output directory with proper name
        ISO_PATH=$(find "${OUTPUT_DIR}/anka-result" -name "*.iso" -type f | head -1)
        if [[ -n "${ISO_PATH}" ]]; then
            cp "${ISO_PATH}" "${OUTPUT_DIR}/${ISO_NAME}"
            echo "[OK] ISO saved to: ${OUTPUT_DIR}/${ISO_NAME}"

            # Generate checksums
            echo "[*] Generating checksums..."
            cd "${OUTPUT_DIR}"
            sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256"
            echo "[OK] Checksum: ${ISO_NAME}.sha256"
        fi
    else
        echo "[ERROR] ISO build failed. Check log: ${LOG_FILE}"
        exit 1
    fi
}

# Show ISO info
show_info() {
    echo ""
    echo "=================================================="
    echo "  ANKA OS ISO Build Complete"
    echo "=================================================="

    if [[ -f "${OUTPUT_DIR}/${ISO_NAME}" ]]; then
        ISO_SIZE=$(du -h "${OUTPUT_DIR}/${ISO_NAME}" | cut -f1)
        echo "  File: ${OUTPUT_DIR}/${ISO_NAME}"
        echo "  Size: ${ISO_SIZE}"
        echo ""
        echo "  To write to USB:"
        echo "  sudo dd if=${OUTPUT_DIR}/${ISO_NAME} of=/dev/sdX bs=4M status=progress"
        echo ""
        echo "  To verify:"
        echo "  sha256sum -c ${OUTPUT_DIR}/${ISO_NAME}.sha256"
    fi
    echo "=================================================="
}

# Main
check_prerequisites
build_iso
show_info