"""
MCP Diagnostics server — read-only system diagnostics.

All tools are readOnly=True, destructiveHint=False. No confirmation required.
Covers logs, disk usage, temperatures, failed services, boot timing,
and detailed memory stats.
"""

from __future__ import annotations

import logging
import subprocess
from pathlib import Path
from typing import Any, Optional

from fastmcp import FastMCP

log = logging.getLogger("anka.mcp.diagnostics")

mcp = FastMCP(
    name="anka-diagnostics",
    description="Read-only system diagnostics: logs, temps, disk, services",
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _run(cmd: list[str], timeout: int = 30) -> subprocess.CompletedProcess[str]:
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
def get_logs(service: Optional[str] = None, lines: int = 50) -> dict[str, Any]:
    """
    Retrieve recent journal log entries.

    Args:
        service: Optional systemd unit name to filter (e.g. 'anka-ai-daemon').
                 None returns kernel + system logs.
        lines: Number of log lines to return (default 50, max 500).

    Returns:
        Dict with 'service', 'lines', and 'entries' list.
    """
    lines = min(max(1, lines), 500)

    cmd = ["journalctl", "--no-pager", f"-n{lines}", "--output=short-iso"]
    if service:
        cmd += ["-u", service]

    result = _run(cmd)
    entries = [ln for ln in result.stdout.splitlines() if ln.strip()]

    return {
        "service": service or "system",
        "lines": len(entries),
        "entries": entries,
    }


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def get_disk_usage() -> list[dict[str, Any]]:
    """
    Return disk usage for all mounted filesystems.

    Returns:
        List of dicts: {filesystem, size, used, available, use_percent, mount}.
    """
    result = _run(["df", "-h", "--output=source,size,used,avail,pcent,target"])
    lines = result.stdout.strip().splitlines()
    entries: list[dict[str, Any]] = []
    for line in lines[1:]:  # skip header
        parts = line.split(None, 5)
        if len(parts) == 6:
            entries.append(
                {
                    "filesystem": parts[0],
                    "size": parts[1],
                    "used": parts[2],
                    "available": parts[3],
                    "use_percent": parts[4],
                    "mount": parts[5],
                }
            )
    return entries


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def get_temperature() -> dict[str, Any]:
    """
    Return CPU and GPU temperatures from hardware sensors.

    Returns:
        Dict with 'sensors' list and 'critical_alerts' list.
    """
    try:
        import psutil

        temps = psutil.sensors_temperatures()
        sensors: list[dict[str, Any]] = []
        alerts: list[str] = []
        for chip_name, readings in temps.items():
            for r in readings:
                entry = {
                    "chip": chip_name,
                    "label": r.label or chip_name,
                    "current_c": r.current,
                    "high_c": r.high,
                    "critical_c": r.critical,
                }
                sensors.append(entry)
                if r.critical and r.current >= r.critical:
                    alerts.append(f"{chip_name}/{r.label}: {r.current}°C (CRITICAL: {r.critical}°C)")
        return {"sensors": sensors, "critical_alerts": alerts}
    except AttributeError:
        pass

    # Fallback: sensors CLI
    result = _run(["sensors"])
    return {"raw_output": result.stdout, "sensors": [], "critical_alerts": []}


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def check_failed_services() -> dict[str, Any]:
    """
    List all systemd units in a failed state.

    Returns:
        Dict with 'failed_count' and 'units' list.
    """
    result = _run(
        [
            "systemctl",
            "--no-pager",
            "list-units",
            "--state=failed",
            "--output=json",
        ]
    )
    units: list[dict[str, Any]] = []
    try:
        import json
        raw = json.loads(result.stdout)
        units = [
            {
                "name": u.get("unit", ""),
                "active_state": u.get("active", ""),
                "sub_state": u.get("sub", ""),
                "description": u.get("description", ""),
            }
            for u in raw
        ]
    except (ValueError, KeyError):
        # Plain text fallback
        for line in result.stdout.splitlines()[1:]:
            parts = line.split(None, 4)
            if len(parts) >= 3:
                units.append({"name": parts[0], "active_state": parts[2]})

    return {"failed_count": len(units), "units": units}


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def get_boot_time() -> dict[str, Any]:
    """
    Return boot performance analysis from systemd-analyze.

    Returns:
        Dict with total_seconds, firmware_seconds, loader_seconds, kernel_seconds,
        userspace_seconds, and slowest_units list.
    """
    # Overall timing
    result = _run(["systemd-analyze"])
    timing: dict[str, Any] = {"raw": result.stdout.strip()}

    # Parse the summary line
    for line in result.stdout.splitlines():
        if "Startup finished" in line or "startup finished" in line:
            import re
            nums = re.findall(r"([\d.]+)s", line)
            keys = ["firmware_seconds", "loader_seconds", "kernel_seconds", "userspace_seconds"]
            for i, key in enumerate(keys):
                if i < len(nums):
                    try:
                        timing[key] = float(nums[i])
                    except ValueError:
                        pass
            if len(nums) > len(keys):
                try:
                    timing["total_seconds"] = float(nums[-1])
                except ValueError:
                    pass

    # Slowest units
    blame_result = _run(["systemd-analyze", "blame", "--no-pager"])
    slow_units: list[dict[str, str]] = []
    for line in blame_result.stdout.splitlines()[:10]:
        parts = line.strip().split(None, 1)
        if len(parts) == 2:
            slow_units.append({"time": parts[0], "unit": parts[1]})

    timing["slowest_units"] = slow_units
    return timing


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def get_memory_details() -> dict[str, Any]:
    """
    Return detailed memory statistics from /proc/meminfo.

    Returns:
        Dict with all /proc/meminfo fields in MB.
    """
    meminfo_path = Path("/proc/meminfo")
    if not meminfo_path.exists():
        return {"error": "/proc/meminfo not available"}

    raw = meminfo_path.read_text(encoding="utf-8")
    result: dict[str, Any] = {}
    for line in raw.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            key = parts[0].rstrip(":")
            try:
                kb_value = int(parts[1])
                # Convert kB → MB
                result[key] = round(kb_value / 1024, 2)
            except ValueError:
                result[key] = parts[1]

    # Compute derived values
    total = result.get("MemTotal", 0)
    available = result.get("MemAvailable", 0)
    if total and available:
        result["UsedPercent"] = round((1 - available / total) * 100, 1)

    return result


if __name__ == "__main__":
    mcp.run()