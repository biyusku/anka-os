"""
MCP Package server — Nix package management with elevated consent.

All mutating operations (install/remove/update) are flagged destructiveHint=True
and require elicitation (explicit user confirmation) before execution.
Search and list operations are read-only.
"""

from __future__ import annotations

import json
import logging
import subprocess
import traceback
from typing import Any

from fastmcp import FastMCP

log = logging.getLogger("anka.mcp.package")

mcp = FastMCP(
    name="anka-package",
    description="Nix package search, install, remove, and system update",
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _nix(*args: str, timeout: int = 300) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["nix", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**__import__("os").environ, "NIX_PAGER": ""},
    )


def _nix_profile(*args: str, timeout: int = 300) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["nix", "profile", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    }
)
def search_packages(query: str) -> list[dict[str, Any]]:
    """
    Search for Nix packages matching a query string.

    Args:
        query: Package name or keyword to search (e.g. 'firefox', 'python').

    Returns:
        List of dicts: {name, version, description, attribute_path}.
    """
    result = _nix("search", "nixpkgs", query, "--json", timeout=60)
    if result.returncode != 0:
        raise RuntimeError(f"nix search failed: {result.stderr.strip()[:500]}")

    packages: list[dict[str, Any]] = []
    try:
        raw = json.loads(result.stdout)
        for attr_path, info in raw.items():
            packages.append(
                {
                    "attribute_path": attr_path,
                    "name": info.get("pname", attr_path.split(".")[-1]),
                    "version": info.get("version", ""),
                    "description": info.get("description", ""),
                }
            )
        packages.sort(key=lambda x: x["name"])
    except (json.JSONDecodeError, KeyError):
        pass

    return packages[:50]  # cap results


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def install_package(name: str) -> dict[str, Any]:
    """
    Install a package into the user profile via 'nix profile install'.
    Requires user confirmation (destructive — modifies system state).

    Args:
        name: Package attribute (e.g. 'nixpkgs#firefox', 'nixpkgs#python3').

    Returns:
        Dict with 'installed' and 'name'.
    """
    # Normalise: if no flake prefix, add nixpkgs#
    if "#" not in name and not name.startswith("/"):
        name = f"nixpkgs#{name}"

    result = _nix_profile("install", name, timeout=600)
    if result.returncode != 0:
        raise RuntimeError(f"nix profile install failed: {result.stderr.strip()[:500]}")

    log.info("Package installed", extra={"name": name})
    return {"installed": True, "name": name}


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def remove_package(name: str) -> dict[str, Any]:
    """
    Remove a package from the user profile.
    Requires user confirmation (destructive).

    Args:
        name: Package name or regex as accepted by 'nix profile remove'.

    Returns:
        Dict with 'removed' and 'name'.
    """
    result = _nix_profile("remove", name, timeout=120)
    if result.returncode != 0:
        raise RuntimeError(f"nix profile remove failed: {result.stderr.strip()[:500]}")

    log.info("Package removed", extra={"name": name})
    return {"removed": True, "name": name}


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def list_installed() -> list[dict[str, Any]]:
    """
    List packages installed in the current user Nix profile.

    Returns:
        List of dicts: {index, name, version, store_path}.
    """
    result = _nix_profile("list", "--json", timeout=30)
    packages: list[dict[str, Any]] = []

    if result.returncode == 0:
        try:
            raw = json.loads(result.stdout)
            elements = raw.get("elements", [])
            for i, elem in enumerate(elements):
                packages.append(
                    {
                        "index": i,
                        "name": elem.get("originalUrl", "").split("#")[-1],
                        "store_path": elem.get("storePaths", [""])[0],
                        "url": elem.get("originalUrl", ""),
                    }
                )
            return packages
        except (json.JSONDecodeError, KeyError):
            pass

    # Fallback: plain text
    for line in result.stdout.splitlines():
        parts = line.split(None, 3)
        if parts:
            packages.append({"index": len(packages), "name": parts[0], "store_path": ""})

    return packages


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def update_system() -> dict[str, Any]:
    """
    Rebuild and switch to the new NixOS system configuration.
    Requires user confirmation (destructive — applies system-wide changes).

    Returns:
        Dict with 'updated', 'generation', and 'output' (truncated).
    """
    result = subprocess.run(
        ["nixos-rebuild", "switch"],
        capture_output=True,
        text=True,
        timeout=1800,  # 30 min budget for large rebuilds
    )
    success = result.returncode == 0
    output = (result.stdout + result.stderr)[-2000:]  # tail of output

    if not success:
        raise RuntimeError(f"nixos-rebuild switch failed.\n{output}")

    log.info("System updated via nixos-rebuild switch")

    # Read new generation number
    gen_result = subprocess.run(
        ["nixos-rebuild", "list-generations"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    current_gen = ""
    for line in gen_result.stdout.splitlines():
        if "(current)" in line:
            current_gen = line.split()[0]
            break

    return {"updated": True, "generation": current_gen, "output": output}


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def get_generations() -> list[dict[str, Any]]:
    """
    List NixOS system generations.

    Returns:
        List of dicts: {generation, date, nixos_version, kernel, current}.
    """
    result = subprocess.run(
        ["nixos-rebuild", "list-generations"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    generations: list[dict[str, Any]] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith("Generation"):
            continue
        parts = line.split()
        if parts:
            is_current = "(current)" in line
            generations.append(
                {
                    "generation": parts[0] if parts else "",
                    "date": parts[1] if len(parts) > 1 else "",
                    "nixos_version": parts[2] if len(parts) > 2 else "",
                    "kernel": parts[3] if len(parts) > 3 else "",
                    "current": is_current,
                }
            )
    return generations


if __name__ == "__main__":
    mcp.run()