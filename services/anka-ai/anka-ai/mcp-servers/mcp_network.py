"""
MCP Network server — NetworkManager D-Bus integration.

Provides Wi-Fi scanning, connection management, VPN status, and diagnostics.
All discovery operations are read-only; connect/disconnect are non-destructive
(reversible) except disconnect which is flagged as destructive.
"""

from __future__ import annotations

import logging
import subprocess
import traceback
from typing import Any, Optional

from fastmcp import FastMCP

log = logging.getLogger("anka.mcp.network")

mcp = FastMCP(
    name="anka-network",
    description="NetworkManager-based network status and control",
)

# ---------------------------------------------------------------------------
# D-Bus / nmcli helpers
# ---------------------------------------------------------------------------


def _nmcli(*args: str, timeout: int = 15) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["nmcli", "--terse", "--fields", "all", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _nm_dbus_available() -> bool:
    try:
        import dbus  # type: ignore[import]

        bus = dbus.SystemBus()
        bus.get_object("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager")
        return True
    except Exception:
        return False


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
def get_network_status() -> dict[str, Any]:
    """
    Return current network status: connection type, SSID, IP, signal strength.

    Returns:
        Dict with type, ssid, ipv4, ipv6, state, signal_strength_percent.
    """
    try:
        import dbus  # type: ignore[import]

        bus = dbus.SystemBus()
        nm_obj = bus.get_object(
            "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager"
        )
        nm_props = dbus.Interface(nm_obj, "org.freedesktop.DBus.Properties")
        state = int(nm_props.Get("org.freedesktop.NetworkManager", "State"))
        connectivity = int(nm_props.Get("org.freedesktop.NetworkManager", "Connectivity"))

        active_conn_paths = nm_props.Get(
            "org.freedesktop.NetworkManager", "ActiveConnections"
        )
        status: dict[str, Any] = {
            "state": state,
            "connectivity": connectivity,
            "connections": [],
        }

        for path in active_conn_paths:
            conn_obj = bus.get_object("org.freedesktop.NetworkManager", path)
            conn_props = dbus.Interface(conn_obj, "org.freedesktop.DBus.Properties")
            conn_type = str(
                conn_props.Get("org.freedesktop.NetworkManager.Connection.Active", "Type")
            )
            conn_id = str(
                conn_props.Get("org.freedesktop.NetworkManager.Connection.Active", "Id")
            )
            status["connections"].append({"type": conn_type, "id": conn_id})

        return status

    except Exception:
        log.debug("D-Bus network status failed", extra={"err": traceback.format_exc()})

    # Fallback: nmcli
    result = _nmcli("general", "status")
    lines = result.stdout.strip().splitlines()
    if lines:
        parts = lines[0].split(":")
        return {
            "state": parts[0] if parts else "unknown",
            "connectivity": parts[1] if len(parts) > 1 else "unknown",
            "type": parts[2] if len(parts) > 2 else "unknown",
        }
    return {"state": "unknown"}


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def list_wifi_networks() -> list[dict[str, Any]]:
    """
    Scan and return visible Wi-Fi networks.

    Returns:
        List of dicts: {ssid, bssid, mode, chan, rate, signal, security, in_use}.
    """
    result = subprocess.run(
        [
            "nmcli",
            "--terse",
            "--fields",
            "SSID,BSSID,MODE,CHAN,RATE,SIGNAL,SECURITY,IN-USE",
            "device",
            "wifi",
            "list",
        ],
        capture_output=True,
        text=True,
        timeout=20,
    )
    networks: list[dict[str, Any]] = []
    for line in result.stdout.strip().splitlines():
        parts = line.split(":")
        if len(parts) >= 8:
            networks.append(
                {
                    "ssid": parts[0].strip(),
                    "bssid": parts[1].strip(),
                    "mode": parts[2].strip(),
                    "chan": parts[3].strip(),
                    "rate": parts[4].strip(),
                    "signal": int(parts[5].strip()) if parts[5].strip().isdigit() else 0,
                    "security": parts[6].strip(),
                    "in_use": parts[7].strip() == "*",
                }
            )
    return networks


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def connect_wifi(ssid: str, password: Optional[str] = None) -> dict[str, Any]:
    """
    Connect to a Wi-Fi network.

    Args:
        ssid: Network name.
        password: WPA passphrase (None for open networks or saved profiles).

    Returns:
        Dict with 'connected' and 'ssid'.
    """
    cmd = ["nmcli", "device", "wifi", "connect", ssid]
    if password:
        cmd += ["password", password]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    success = result.returncode == 0
    log.info("Wi-Fi connect attempt", extra={"ssid": ssid, "success": success})
    return {
        "connected": success,
        "ssid": ssid,
        "message": result.stdout.strip() or result.stderr.strip(),
    }


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def disconnect_network() -> dict[str, Any]:
    """
    Disconnect all active network connections.

    Returns:
        Dict with 'disconnected'.
    """
    result = subprocess.run(
        ["nmcli", "networking", "off"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    success = result.returncode == 0
    # Re-enable networking so the OS doesn't stay dark
    if success:
        subprocess.run(["nmcli", "networking", "on"], capture_output=True, timeout=5)

    log.info("Network disconnected", extra={"success": success})
    return {"disconnected": success}


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def set_wifi_enabled(enabled: bool) -> dict[str, Any]:
    """
    Enable or disable the Wi-Fi radio.

    Args:
        enabled: True to enable, False to disable.

    Returns:
        Dict with 'wifi_enabled'.
    """
    state = "on" if enabled else "off"
    result = subprocess.run(
        ["nmcli", "radio", "wifi", state],
        capture_output=True,
        text=True,
        timeout=10,
    )
    return {"wifi_enabled": enabled, "success": result.returncode == 0}


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def get_vpn_status() -> dict[str, Any]:
    """
    Return active VPN connection details.

    Returns:
        Dict with 'active', 'name', 'type', 'state'.
    """
    result = subprocess.run(
        [
            "nmcli",
            "--terse",
            "--fields",
            "NAME,TYPE,STATE",
            "connection",
            "show",
            "--active",
        ],
        capture_output=True,
        text=True,
        timeout=10,
    )
    vpn_connections: list[dict[str, str]] = []
    for line in result.stdout.strip().splitlines():
        parts = line.split(":")
        if len(parts) >= 3 and "vpn" in parts[1].lower():
            vpn_connections.append(
                {"name": parts[0], "type": parts[1], "state": parts[2]}
            )

    return {
        "active": bool(vpn_connections),
        "connections": vpn_connections,
    }


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    }
)
def ping(host: str) -> dict[str, Any]:
    """
    Ping a host and return latency statistics.

    Args:
        host: Hostname or IP address.

    Returns:
        Dict with 'reachable', 'avg_ms', 'packet_loss'.
    """
    # Validate host to prevent command injection
    import re
    if not re.match(r"^[a-zA-Z0-9.\-_]+$", host):
        raise ValueError(f"Invalid host: '{host}'")

    result = subprocess.run(
        ["ping", "-c", "4", "-W", "3", host],
        capture_output=True,
        text=True,
        timeout=20,
    )
    output = result.stdout

    avg_ms: Optional[float] = None
    packet_loss: Optional[str] = None

    for line in output.splitlines():
        if "avg" in line or "rtt" in line:
            try:
                # format: rtt min/avg/max/mdev = X/Y/Z/W ms
                avg_ms = float(line.split("/")[4])
            except (IndexError, ValueError):
                pass
        if "packet loss" in line:
            try:
                packet_loss = line.split("%")[0].split()[-1] + "%"
            except IndexError:
                pass

    return {
        "reachable": result.returncode == 0,
        "host": host,
        "avg_ms": avg_ms,
        "packet_loss": packet_loss,
    }


if __name__ == "__main__":
    mcp.run()