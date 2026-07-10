"""
MCP Desktop server — KWin / KDE Plasma desktop control.

Uses D-Bus for KWin integration (KWin ScreenShot2, KWindowSystem).
Falls back to CLI tools (scrot, xdotool, ydotool, pactl, brightnessctl)
when D-Bus is unavailable.
"""

from __future__ import annotations

import base64
import logging
import os
import subprocess
import tempfile
import traceback
from typing import Any, Optional

from fastmcp import FastMCP

log = logging.getLogger("anka.mcp.desktop")

mcp = FastMCP(
    name="anka-desktop",
    description="KDE Plasma desktop control: windows, audio, brightness, input",
)

# ---------------------------------------------------------------------------
# D-Bus helpers
# ---------------------------------------------------------------------------

_DBUS_AVAILABLE: Optional[bool] = None


def _dbus_available() -> bool:
    global _DBUS_AVAILABLE
    if _DBUS_AVAILABLE is None:
        try:
            import dbus  # type: ignore[import]
            _DBUS_AVAILABLE = True
        except ImportError:
            _DBUS_AVAILABLE = False
    return _DBUS_AVAILABLE


def _kwin_dbus() -> Any:
    """Return the KWin org.kde.KWin.ScreenShot2 proxy, or None."""
    try:
        import dbus  # type: ignore[import]

        bus = dbus.SessionBus()
        obj = bus.get_object("org.kde.KWin", "/Screenshot")
        return dbus.Interface(obj, "org.kde.KWin.ScreenShot2")
    except Exception:
        return None


def _nm_dbus() -> Any:
    """Return the org.kde.plasmashell proxy for window listing, or None."""
    try:
        import dbus  # type: ignore[import]

        bus = dbus.SessionBus()
        return bus.get_object("org.kde.KWin", "/KWin")
    except Exception:
        return None


def _run(cmd: list[str], timeout: int = 10) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def screenshot() -> dict[str, Any]:
    """
    Capture the current screen and return a base64-encoded PNG.

    Returns:
        Dict with 'image_b64' (base64 PNG) and 'format' = 'png'.
    """
    # Try KWin ScreenShot2 first
    iface = _kwin_dbus()
    if iface is not None:
        try:
            with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
                tmp_path = tmp.name
            iface.screenshotFullscreen(tmp_path)
            with open(tmp_path, "rb") as f:
                data = f.read()
            os.unlink(tmp_path)
            return {"image_b64": base64.b64encode(data).decode(), "format": "png"}
        except Exception:
            log.debug("KWin screenshot failed", extra={"err": traceback.format_exc()})

    # Fallback: scrot
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        result = _run(["scrot", tmp_path])
        if result.returncode == 0:
            with open(tmp_path, "rb") as f:
                data = f.read()
            return {"image_b64": base64.b64encode(data).decode(), "format": "png"}
    except FileNotFoundError:
        pass
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    raise RuntimeError("Screenshot unavailable: neither KWin D-Bus nor scrot found")


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def list_windows() -> list[dict[str, Any]]:
    """
    Return a list of open windows with id, title, geometry, and state.

    Returns:
        List of window dicts.
    """
    try:
        import dbus  # type: ignore[import]

        bus = dbus.SessionBus()
        obj = bus.get_object("org.kde.KWin", "/KWin")
        iface = dbus.Interface(obj, "org.kde.KWin")
        windows = iface.getWindowList()  # returns list of window IDs
        result: list[dict[str, Any]] = []
        for wid in windows:
            try:
                win_obj = bus.get_object("org.kde.KWin", f"/KWin/Window/{wid}")
                props = dbus.Interface(win_obj, "org.freedesktop.DBus.Properties")
                result.append(
                    {
                        "id": int(wid),
                        "title": str(props.Get("org.kde.KWin.Window", "caption")),
                        "active": bool(props.Get("org.kde.KWin.Window", "active")),
                        "minimized": bool(props.Get("org.kde.KWin.Window", "minimized")),
                    }
                )
            except Exception:
                result.append({"id": int(wid), "title": "unknown"})
        return result
    except Exception:
        # Fallback: wmctrl
        result_list: list[dict[str, Any]] = []
        try:
            proc = _run(["wmctrl", "-l"])
            for line in proc.stdout.splitlines():
                parts = line.split(None, 3)
                if len(parts) >= 4:
                    result_list.append({"id": parts[0], "title": parts[3]})
        except FileNotFoundError:
            pass
        return result_list


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def focus_window(window_id: int) -> dict[str, Any]:
    """
    Bring a window to focus by its ID.

    Args:
        window_id: Window ID as returned by list_windows.

    Returns:
        Dict with 'success' and 'window_id'.
    """
    try:
        import dbus  # type: ignore[import]

        bus = dbus.SessionBus()
        obj = bus.get_object("org.kde.KWin", "/KWin")
        iface = dbus.Interface(obj, "org.kde.KWin")
        iface.activateWindow(window_id)
        return {"success": True, "window_id": window_id}
    except Exception:
        # Fallback: wmctrl
        result = _run(["wmctrl", "-ia", hex(window_id)])
        return {"success": result.returncode == 0, "window_id": window_id}


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def move_window(window_id: int, x: int, y: int) -> dict[str, Any]:
    """
    Move a window to absolute screen coordinates.

    Args:
        window_id: Target window ID.
        x: Horizontal position in pixels.
        y: Vertical position in pixels.

    Returns:
        Dict with 'success'.
    """
    try:
        result = _run(["wmctrl", "-ir", hex(window_id), "-e", f"0,{x},{y},-1,-1"])
        return {"success": result.returncode == 0, "window_id": window_id, "x": x, "y": y}
    except FileNotFoundError:
        raise RuntimeError("wmctrl not found — cannot move window")


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def set_volume(level: int) -> dict[str, Any]:
    """
    Set the default audio sink volume (0–100).

    Args:
        level: Volume percentage, 0 to 100.

    Returns:
        Dict with 'volume_set'.
    """
    if not 0 <= level <= 100:
        raise ValueError(f"Volume must be 0–100, got {level}")

    result = _run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{level}%"])
    if result.returncode != 0:
        raise RuntimeError(f"pactl failed: {result.stderr.strip()}")

    log.info("Volume set", extra={"level": level})
    return {"volume_set": level}


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def set_brightness(level: int) -> dict[str, Any]:
    """
    Set screen brightness (0–100).

    Args:
        level: Brightness percentage, 0 to 100.

    Returns:
        Dict with 'brightness_set'.
    """
    if not 0 <= level <= 100:
        raise ValueError(f"Brightness must be 0–100, got {level}")

    result = _run(["brightnessctl", "set", f"{level}%"])
    if result.returncode != 0:
        raise RuntimeError(f"brightnessctl failed: {result.stderr.strip()}")

    log.info("Brightness set", extra={"level": level})
    return {"brightness_set": level}


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def get_active_window() -> dict[str, Any]:
    """
    Return information about the currently focused window.

    Returns:
        Dict with id, title, class, geometry.
    """
    try:
        proc = _run(["xdotool", "getactivewindow"])
        wid = proc.stdout.strip()
        title_proc = _run(["xdotool", "getwindowname", wid])
        class_proc = _run(["xdotool", "getwindowclassname", wid])
        return {
            "id": wid,
            "title": title_proc.stdout.strip(),
            "class": class_proc.stdout.strip(),
        }
    except FileNotFoundError:
        return {"id": None, "title": "unknown", "class": "unknown"}


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def type_text(text: str) -> dict[str, Any]:
    """
    Type text into the currently focused window using ydotool or xdotool.

    Args:
        text: The text to type.

    Returns:
        Dict with 'typed' (length of typed text).
    """
    # Prefer ydotool (Wayland) over xdotool (X11)
    for tool, cmd in [
        ("ydotool", ["ydotool", "type", "--", text]),
        ("xdotool", ["xdotool", "type", "--clearmodifiers", "--", text]),
    ]:
        try:
            result = _run(cmd)
            if result.returncode == 0:
                return {"typed": len(text), "tool": tool}
        except FileNotFoundError:
            continue

    raise RuntimeError("No typing tool found (ydotool or xdotool required)")


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def key_press(key: str) -> dict[str, Any]:
    """
    Simulate a key press (e.g. 'ctrl+c', 'Return', 'super+l').

    Args:
        key: Key or key combination string.

    Returns:
        Dict with 'key' and 'tool' used.
    """
    for tool, cmd in [
        ("ydotool", ["ydotool", "key", "--", key]),
        ("xdotool", ["xdotool", "key", "--clearmodifiers", key]),
    ]:
        try:
            result = _run(cmd)
            if result.returncode == 0:
                return {"key": key, "tool": tool}
        except FileNotFoundError:
            continue

    raise RuntimeError("No key-press tool found (ydotool or xdotool required)")


if __name__ == "__main__":
    mcp.run()