"""
MCP Filesystem server — secure file operations with path validation.

All paths are resolved to real paths via os.path.realpath() and checked
against a byte-exact prefix list to prevent symlink traversal attacks.
Allowed roots are loaded from ~/.config/anka/mcp-roots.json.
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
from pathlib import Path
from typing import Any, Optional

from fastmcp import FastMCP

log = logging.getLogger("anka.mcp.filesystem")

# ---------------------------------------------------------------------------
# Server setup
# ---------------------------------------------------------------------------

mcp = FastMCP(
    name="anka-filesystem",
    description="Secure filesystem operations with sandboxed root enforcement",
)

# ---------------------------------------------------------------------------
# Root loading
# ---------------------------------------------------------------------------

_ROOTS_CONFIG = Path.home() / ".config" / "anka" / "mcp-roots.json"

_DEFAULT_ROOTS: list[str] = [
    str(Path.home()),
    "/tmp",
]


def _load_roots() -> list[bytes]:
    """Return byte-exact root prefixes for safe prefix matching."""
    try:
        data = json.loads(_ROOTS_CONFIG.read_text(encoding="utf-8"))
        paths: list[str] = data.get("roots", _DEFAULT_ROOTS)
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        paths = _DEFAULT_ROOTS

    result: list[bytes] = []
    for p in paths:
        real = os.path.realpath(p)
        # Normalise trailing separator for prefix matching
        if not real.endswith(os.sep):
            real += os.sep
        result.append(real.encode())
    return result


def _is_allowed(path: str) -> tuple[bool, str]:
    """
    Validate that *path* is inside an allowed root after full symlink resolution.

    Returns (is_allowed, real_path).
    """
    real = os.path.realpath(path)
    real_bytes = (real + os.sep).encode() if not real.endswith(os.sep) else real.encode()

    for root in _load_roots():
        if real_bytes.startswith(root):
            return True, real

    return False, real


def _guard(path: str) -> str:
    """Raise ValueError if path is outside allowed roots, else return real path."""
    allowed, real = _is_allowed(path)
    if not allowed:
        raise ValueError(
            f"Access denied: '{path}' resolves to '{real}' which is outside allowed roots"
        )
    return real


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def read_file(path: str, encoding: str = "utf-8") -> str:
    """
    Read and return the contents of a file.

    Args:
        path: Absolute or relative path to the file.
        encoding: Text encoding (default utf-8). Use 'binary' to get hex.

    Returns:
        File contents as a string, or hex-encoded bytes if encoding='binary'.
    """
    real = _guard(path)
    file_path = Path(real)
    if not file_path.is_file():
        raise FileNotFoundError(f"No file at '{real}'")

    if encoding == "binary":
        return file_path.read_bytes().hex()

    return file_path.read_text(encoding=encoding)


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def write_file(path: str, content: str, encoding: str = "utf-8") -> dict[str, Any]:
    """
    Write content to a file, creating parent directories as needed.

    Args:
        path: Destination path.
        content: Text to write.
        encoding: Text encoding (default utf-8).

    Returns:
        Dict with 'path' and 'bytes_written'.
    """
    real = _guard(path)
    file_path = Path(real)
    file_path.parent.mkdir(parents=True, exist_ok=True)
    data = content.encode(encoding)
    file_path.write_bytes(data)
    log.info("File written", extra={"path": real, "bytes": len(data)})
    return {"path": real, "bytes_written": len(data)}


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def list_directory(path: str) -> list[dict[str, Any]]:
    """
    List directory contents with metadata.

    Args:
        path: Directory path to list.

    Returns:
        List of dicts: {name, type, size, modified}.
    """
    real = _guard(path)
    dir_path = Path(real)
    if not dir_path.is_dir():
        raise NotADirectoryError(f"'{real}' is not a directory")

    entries: list[dict[str, Any]] = []
    for entry in sorted(dir_path.iterdir()):
        try:
            stat = entry.stat(follow_symlinks=False)
            entries.append(
                {
                    "name": entry.name,
                    "type": "directory" if entry.is_dir() else "symlink" if entry.is_symlink() else "file",
                    "size": stat.st_size,
                    "modified": stat.st_mtime,
                }
            )
        except OSError:
            entries.append({"name": entry.name, "type": "unknown", "size": 0, "modified": 0})

    return entries


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def search_files(pattern: str, directory: str) -> list[str]:
    """
    Search for files matching a glob or regex pattern using ripgrep.

    Args:
        pattern: Search pattern (passed to rg --files-with-matches or glob).
        directory: Root directory for search.

    Returns:
        List of matching absolute file paths.
    """
    real_dir = _guard(directory)
    try:
        result = subprocess.run(
            ["rg", "--files", "--glob", pattern, real_dir],
            capture_output=True,
            text=True,
            timeout=30,
        )
        lines = [ln.strip() for ln in result.stdout.splitlines() if ln.strip()]
        # Security: filter results to confirmed allowed paths
        return [ln for ln in lines if _is_allowed(ln)[0]]
    except FileNotFoundError:
        # ripgrep not available — fall back to pathlib glob
        dir_path = Path(real_dir)
        return [
            str(p)
            for p in dir_path.rglob(pattern)
            if _is_allowed(str(p))[0]
        ]


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def get_file_info(path: str) -> dict[str, Any]:
    """
    Return metadata for a file or directory.

    Args:
        path: Path to inspect.

    Returns:
        Dict with size, permissions, owner, modified, created, mime_type (best-effort).
    """
    real = _guard(path)
    p = Path(real)
    if not p.exists():
        raise FileNotFoundError(f"No entry at '{real}'")

    stat = p.stat(follow_symlinks=False)
    info: dict[str, Any] = {
        "path": real,
        "type": "directory" if p.is_dir() else "symlink" if p.is_symlink() else "file",
        "size": stat.st_size,
        "permissions": oct(stat.st_mode),
        "uid": stat.st_uid,
        "gid": stat.st_gid,
        "modified": stat.st_mtime,
        "created": stat.st_ctime,
    }

    # Best-effort MIME type
    try:
        import mimetypes
        mime, _ = mimetypes.guess_type(real)
        info["mime_type"] = mime or "application/octet-stream"
    except Exception:
        info["mime_type"] = "unknown"

    return info


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def delete_file(path: str) -> dict[str, str]:
    """
    Delete a file (NOT a directory). Requires elicitation confirmation upstream.

    Args:
        path: Path to delete.

    Returns:
        Dict with 'deleted' path.
    """
    real = _guard(path)
    p = Path(real)
    if p.is_dir():
        raise IsADirectoryError(f"'{real}' is a directory — use rmdir tools for directories")
    if not p.exists():
        raise FileNotFoundError(f"No file at '{real}'")

    p.unlink()
    log.info("File deleted", extra={"path": real})
    return {"deleted": real}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run()