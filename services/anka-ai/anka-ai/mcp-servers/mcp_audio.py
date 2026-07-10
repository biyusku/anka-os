"""
MCP Audio server — PipeWire / PulseAudio control.

Uses pactl (PulseAudio-compatible CLI, works under PipeWire-pulse) for all
operations. Falls back to pw-cli for PipeWire-native queries where needed.
All volume levels are 0–100 integer percentages.
"""

from __future__ import annotations

import logging
import subprocess
import traceback
from typing import Any, Optional

from fastmcp import FastMCP

log = logging.getLogger("anka.mcp.audio")

mcp = FastMCP(
    name="anka-audio",
    description="PipeWire/PulseAudio volume, mute, and device control",
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _pactl(*args: str, timeout: int = 10) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["pactl", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _parse_pactl_info(output: str) -> dict[str, str]:
    """Parse 'pactl info' key: value output into a dict."""
    result: dict[str, str] = {}
    for line in output.splitlines():
        if ": " in line:
            key, _, value = line.partition(": ")
            result[key.strip()] = value.strip()
    return result


def _parse_sink_list(output: str) -> list[dict[str, Any]]:
    """Parse 'pactl list sinks' into a list of sink dicts."""
    sinks: list[dict[str, Any]] = []
    current: dict[str, Any] = {}
    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith("Sink #"):
            if current:
                sinks.append(current)
            current = {"id": stripped.split("#")[1]}
        elif stripped.startswith("Name: "):
            current["name"] = stripped[6:]
        elif stripped.startswith("Description: "):
            current["description"] = stripped[13:]
        elif stripped.startswith("State: "):
            current["state"] = stripped[7:]
        elif "Volume:" in stripped and "front-left" in stripped:
            try:
                pct = stripped.split("%")[0].split()[-1]
                current["volume_percent"] = int(pct)
            except (IndexError, ValueError):
                pass
        elif stripped.startswith("Mute: "):
            current["muted"] = stripped[6:].strip().lower() == "yes"
    if current:
        sinks.append(current)
    return sinks


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
def get_audio_status() -> dict[str, Any]:
    """
    Return current audio status: volume, mute state, default sink and source.

    Returns:
        Dict with volume_percent, muted, default_sink, default_source.
    """
    try:
        info_result = _pactl("info")
        info = _parse_pactl_info(info_result.stdout)
        default_sink = info.get("Default Sink", "unknown")
        default_source = info.get("Default Source", "unknown")

        # Get volume of default sink
        vol_result = _pactl("get-sink-volume", "@DEFAULT_SINK@")
        volume_percent: Optional[int] = None
        for part in vol_result.stdout.split():
            if part.endswith("%"):
                try:
                    volume_percent = int(part.rstrip("%"))
                    break
                except ValueError:
                    pass

        mute_result = _pactl("get-sink-mute", "@DEFAULT_SINK@")
        muted = "yes" in mute_result.stdout.lower()

        return {
            "volume_percent": volume_percent,
            "muted": muted,
            "default_sink": default_sink,
            "default_source": default_source,
        }
    except Exception:
        log.warning("get_audio_status failed", extra={"err": traceback.format_exc()})
        return {"volume_percent": None, "muted": None, "default_sink": None, "default_source": None}


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
    Set the default audio output volume.

    Args:
        level: Volume percentage 0–100.

    Returns:
        Dict with 'volume_set'.
    """
    if not 0 <= level <= 100:
        raise ValueError(f"Volume must be 0–100, got {level}")

    result = _pactl("set-sink-volume", "@DEFAULT_SINK@", f"{level}%")
    if result.returncode != 0:
        raise RuntimeError(f"pactl set-sink-volume failed: {result.stderr.strip()}")

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
def toggle_mute() -> dict[str, Any]:
    """
    Toggle mute on the default audio output.

    Returns:
        Dict with 'muted' reflecting the new state.
    """
    result = _pactl("set-sink-mute", "@DEFAULT_SINK@", "toggle")
    if result.returncode != 0:
        raise RuntimeError(f"pactl toggle mute failed: {result.stderr.strip()}")

    # Read back new state
    mute_result = _pactl("get-sink-mute", "@DEFAULT_SINK@")
    muted = "yes" in mute_result.stdout.lower()
    log.info("Mute toggled", extra={"muted": muted})
    return {"muted": muted}


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def list_audio_devices() -> dict[str, Any]:
    """
    List all audio sinks (outputs) and sources (inputs).

    Returns:
        Dict with 'sinks' and 'sources' lists.
    """
    sinks_result = _pactl("list", "sinks")
    sources_result = _pactl("list", "sources")

    sinks = _parse_sink_list(sinks_result.stdout)
    sources = _parse_sink_list(sources_result.stdout)  # same format

    return {"sinks": sinks, "sources": sources}


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def set_default_sink(device_name: str) -> dict[str, Any]:
    """
    Set the default audio output device.

    Args:
        device_name: Sink name as returned by list_audio_devices.

    Returns:
        Dict with 'default_sink'.
    """
    result = _pactl("set-default-sink", device_name)
    if result.returncode != 0:
        raise RuntimeError(f"pactl set-default-sink failed: {result.stderr.strip()}")

    log.info("Default sink changed", extra={"sink": device_name})
    return {"default_sink": device_name}


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def set_default_source(device_name: str) -> dict[str, Any]:
    """
    Set the default audio input device (microphone).

    Args:
        device_name: Source name as returned by list_audio_devices.

    Returns:
        Dict with 'default_source'.
    """
    result = _pactl("set-default-source", device_name)
    if result.returncode != 0:
        raise RuntimeError(f"pactl set-default-source failed: {result.stderr.strip()}")

    log.info("Default source changed", extra={"source": device_name})
    return {"default_source": device_name}


if __name__ == "__main__":
    mcp.run()