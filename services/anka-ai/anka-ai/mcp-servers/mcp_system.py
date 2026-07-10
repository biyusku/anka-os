"""
MCP System server — systemd service management and system control.

Privilege separation pattern: all mutating operations go through D-Bus to
systemd (org.freedesktop.systemd1), timedatectl, and hostnamectl rather than
spawning privileged subprocesses. Destructive tools require elicitation.
"""

from __future__ import annotations

import logging
import subprocess
import traceback
from typing import Any, Optional

from fastmcp import FastMCP

log = logging.getLogger("anka.mcp.system")

mcp = FastMCP(
    name="anka-system",
    description="Systemd service control, timezone/hostname management, and system info",
)

# ---------------------------------------------------------------------------
# D-Bus / systemd helpers
# ---------------------------------------------------------------------------


def _systemctl(*args: str, timeout: int = 15) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["systemctl", "--no-pager", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _sd_dbus_manager() -> Any:
    """Return org.freedesktop.systemd1.Manager proxy, or None."""
    try:
        import dbus  # type: ignore[import]

        bus = dbus.SystemBus()
        obj = bus.get_object(
            "org.freedesktop.systemd1", "/org/freedesktop/systemd1"
        )
        return dbus.Interface(obj, "org.freedesktop.systemd1.Manager")
    except Exception:
        return None


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
def list_services() -> list[dict[str, Any]]:
    """
    List all loaded systemd units with their state.

    Returns:
        List of dicts: {name, load_state, active_state, sub_state, description}.
    """
    result = _systemctl(
        "list-units",
        "--type=service",
        "--output=json",
        "--all",
    )
    if result.returncode != 0:
        # Fallback: plain text parse
        services: list[dict[str, Any]] = []
        for line in result.stdout.splitlines()[1:]:
            parts = line.split(None, 4)
            if len(parts) >= 4:
                services.append(
                    {
                        "name": parts[0],
                        "load_state": parts[1],
                        "active_state": parts[2],
                        "sub_state": parts[3],
                        "description": parts[4] if len(parts) > 4 else "",
                    }
                )
        return services

    try:
        import json
        units = json.loads(result.stdout)
        return [
            {
                "name": u.get("unit", ""),
                "load_state": u.get("load", ""),
                "active_state": u.get("active", ""),
                "sub_state": u.get("sub", ""),
                "description": u.get("description", ""),
            }
            for u in units
        ]
    except (ValueError, KeyError):
        return []


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def get_service_status(name: str) -> dict[str, Any]:
    """
    Return detailed status for a systemd service.

    Args:
        name: Service name (e.g. 'nginx', 'sshd', 'anka-ai-daemon').

    Returns:
        Dict with active_state, sub_state, pid, memory_mb, cpu_percent, since.
    """
    result = _systemctl("show", "--property=ActiveState,SubState,MainPID,MemoryCurrent,CPUUsageNSec,ActiveEnterTimestamp", name)
    props: dict[str, str] = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            props[k.strip()] = v.strip()

    mem_bytes = int(props.get("MemoryCurrent", "0") or "0")
    cpu_ns = int(props.get("CPUUsageNSec", "0") or "0")

    return {
        "name": name,
        "active_state": props.get("ActiveState", "unknown"),
        "sub_state": props.get("SubState", "unknown"),
        "main_pid": int(props.get("MainPID", "0") or "0"),
        "memory_mb": round(mem_bytes / (1024 * 1024), 2) if mem_bytes else None,
        "cpu_usage_seconds": round(cpu_ns / 1e9, 3) if cpu_ns else None,
        "active_since": props.get("ActiveEnterTimestamp", ""),
    }


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def restart_service(name: str) -> dict[str, Any]:
    """
    Restart a systemd service. Requires user confirmation (destructive).

    Args:
        name: Service name to restart.

    Returns:
        Dict with 'restarted' and 'name'.
    """
    # Use D-Bus for privilege separation when available
    manager = _sd_dbus_manager()
    if manager is not None:
        try:
            manager.RestartUnit(f"{name}.service", "replace")
            log.info("Service restarted via D-Bus", extra={"service": name})
            return {"restarted": True, "name": name, "method": "dbus"}
        except Exception:
            log.debug("D-Bus restart failed", extra={"err": traceback.format_exc()})

    result = _systemctl("restart", name)
    success = result.returncode == 0
    if not success:
        raise RuntimeError(f"systemctl restart {name} failed: {result.stderr.strip()}")

    log.info("Service restarted via CLI", extra={"service": name})
    return {"restarted": True, "name": name, "method": "cli"}


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def get_system_info() -> dict[str, Any]:
    """
    Return static system information.

    Returns:
        Dict with hostname, os_version, kernel, architecture, uptime_seconds.
    """
    import platform
    import time

    import psutil

    uname = platform.uname()
    uptime_seconds = round(time.time() - psutil.boot_time())

    # OS release info
    os_release: dict[str, str] = {}
    try:
        with open("/etc/os-release") as f:
            for line in f:
                line = line.strip()
                if "=" in line:
                    k, _, v = line.partition("=")
                    os_release[k] = v.strip('"')
    except FileNotFoundError:
        pass

    return {
        "hostname": uname.node,
        "os_name": os_release.get("PRETTY_NAME", uname.system),
        "os_id": os_release.get("ID", ""),
        "os_version": os_release.get("VERSION_ID", ""),
        "kernel": uname.release,
        "architecture": uname.machine,
        "processor": uname.processor or uname.machine,
        "uptime_seconds": uptime_seconds,
    }


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def set_timezone(tz: str) -> dict[str, Any]:
    """
    Set the system timezone via timedatectl D-Bus.

    Args:
        tz: IANA timezone string (e.g. 'Europe/Istanbul', 'UTC').

    Returns:
        Dict with 'timezone_set'.
    """
    # Validate: must be a recognisable IANA tz
    import re
    if not re.match(r"^[A-Za-z]+(/[A-Za-z_\-+0-9]+){0,2}$", tz) and tz != "UTC":
        raise ValueError(f"Invalid timezone format: '{tz}'")

    try:
        import dbus  # type: ignore[import]

        bus = dbus.SystemBus()
        obj = bus.get_object("org.freedesktop.timedate1", "/org/freedesktop/timedate1")
        iface = dbus.Interface(obj, "org.freedesktop.timedate1")
        iface.SetTimezone(tz, False)
        log.info("Timezone set via D-Bus", extra={"tz": tz})
        return {"timezone_set": tz, "method": "dbus"}
    except Exception:
        log.debug("D-Bus timezone set failed", extra={"err": traceback.format_exc()})

    result = subprocess.run(
        ["timedatectl", "set-timezone", tz],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if result.returncode != 0:
        raise RuntimeError(f"timedatectl failed: {result.stderr.strip()}")

    log.info("Timezone set via CLI", extra={"tz": tz})
    return {"timezone_set": tz, "method": "cli"}


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def set_hostname(name: str) -> dict[str, Any]:
    """
    Set the system hostname via hostnamectl D-Bus.

    Args:
        name: New hostname (RFC 1123 format).

    Returns:
        Dict with 'hostname_set'.
    """
    import re
    if not re.match(r"^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$", name):
        raise ValueError(f"Invalid hostname: '{name}'")

    try:
        import dbus  # type: ignore[import]

        bus = dbus.SystemBus()
        obj = bus.get_object("org.freedesktop.hostname1", "/org/freedesktop/hostname1")
        iface = dbus.Interface(obj, "org.freedesktop.hostname1")
        iface.SetHostname(name, False)
        log.info("Hostname set via D-Bus", extra={"hostname": name})
        return {"hostname_set": name, "method": "dbus"}
    except Exception:
        log.debug("D-Bus hostname set failed", extra={"err": traceback.format_exc()})

    result = subprocess.run(
        ["hostnamectl", "set-hostname", name],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if result.returncode != 0:
        raise RuntimeError(f"hostnamectl failed: {result.stderr.strip()}")

    return {"hostname_set": name, "method": "cli"}


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def schedule_shutdown(minutes: int) -> dict[str, Any]:
    """
    Schedule a system shutdown. Requires user confirmation (destructive).

    Args:
        minutes: Minutes until shutdown (0 for immediate, max 1440).

    Returns:
        Dict with 'shutdown_scheduled_at_minutes'.
    """
    if not 0 <= minutes <= 1440:
        raise ValueError(f"Minutes must be 0–1440, got {minutes}")

    time_arg = "now" if minutes == 0 else f"+{minutes}"
    result = subprocess.run(
        ["shutdown", time_arg],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if result.returncode != 0:
        raise RuntimeError(f"shutdown failed: {result.stderr.strip()}")

    log.info("Shutdown scheduled", extra={"minutes": minutes})
    return {"shutdown_scheduled_at_minutes": minutes}


if __name__ == "__main__":
    mcp.run()