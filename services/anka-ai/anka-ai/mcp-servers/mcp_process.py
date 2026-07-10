"""
MCP Process server — system process and resource management.

Uses psutil for cross-version compatibility. kill_process requires elicitation
(destructiveHint=True). All read operations are non-destructive.
"""

from __future__ import annotations

import logging
import os
import signal as _signal
from typing import Any

import psutil
from fastmcp import FastMCP

log = logging.getLogger("anka.mcp.process")

mcp = FastMCP(
    name="anka-process",
    description="Process listing, resource stats, and controlled process termination",
)

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
def list_processes() -> list[dict[str, Any]]:
    """
    Return a list of running processes with resource usage.

    Returns:
        List of dicts: {pid, name, cpu_percent, mem_percent, user, status, cmdline}.
    """
    result: list[dict[str, Any]] = []
    for proc in psutil.process_iter(
        ["pid", "name", "cpu_percent", "memory_percent", "username", "status", "cmdline"]
    ):
        try:
            info = proc.info
            result.append(
                {
                    "pid": info["pid"],
                    "name": info["name"] or "",
                    "cpu_percent": round(info["cpu_percent"] or 0.0, 2),
                    "mem_percent": round(info["memory_percent"] or 0.0, 2),
                    "user": info["username"] or "",
                    "status": info["status"] or "",
                    "cmdline": (info["cmdline"] or [])[:3],
                }
            )
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return sorted(result, key=lambda x: x["cpu_percent"], reverse=True)


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }
)
def get_process_info(pid: int) -> dict[str, Any]:
    """
    Return detailed information for a specific process.

    Args:
        pid: Process ID.

    Returns:
        Dict with pid, name, exe, status, cpu, memory, threads, open_files count.
    """
    try:
        proc = psutil.Process(pid)
        with proc.oneshot():
            mem = proc.memory_info()
            return {
                "pid": proc.pid,
                "name": proc.name(),
                "exe": proc.exe() or None,
                "status": proc.status(),
                "cpu_percent": round(proc.cpu_percent(interval=0.1), 2),
                "mem_rss_mb": round(mem.rss / (1024 * 1024), 2),
                "mem_vms_mb": round(mem.vms / (1024 * 1024), 2),
                "threads": proc.num_threads(),
                "open_files": len(proc.open_files()),
                "create_time": proc.create_time(),
                "parent_pid": proc.ppid(),
                "user": proc.username(),
                "cmdline": proc.cmdline(),
            }
    except psutil.NoSuchProcess:
        raise ValueError(f"No process with PID {pid}")
    except psutil.AccessDenied:
        return {"pid": pid, "error": "Access denied"}


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def kill_process(pid: int, signal: str = "SIGTERM") -> dict[str, Any]:
    """
    Send a signal to a process. Requires user confirmation (destructive).

    Args:
        pid: Target process ID.
        signal: Signal name — SIGTERM, SIGKILL, SIGINT, or SIGHUP. Default SIGTERM.

    Returns:
        Dict with 'sent', 'pid', 'signal', 'name'.
    """
    _ALLOWED: dict[str, _signal.Signals] = {
        "SIGTERM": _signal.SIGTERM,
        "SIGKILL": _signal.SIGKILL,
        "SIGINT": _signal.SIGINT,
        "SIGHUP": _signal.SIGHUP,
    }
    sig = _ALLOWED.get(signal.upper())
    if sig is None:
        raise ValueError(f"Unsupported signal '{signal}'. Allowed: {list(_ALLOWED)}")

    if pid in (0, 1):
        raise PermissionError("Refusing to signal PID 0 or 1")

    try:
        proc = psutil.Process(pid)
        name = proc.name()
        proc.send_signal(sig)
        log.info("Signal sent", extra={"pid": pid, "signal": signal, "name": name})
        return {"sent": True, "pid": pid, "signal": signal, "name": name}
    except psutil.NoSuchProcess:
        raise ValueError(f"No process with PID {pid}")
    except psutil.AccessDenied:
        raise PermissionError(f"Access denied for PID {pid}")


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def get_system_stats() -> dict[str, Any]:
    """
    Return current system resource statistics.

    Returns:
        Dict with cpu_percent, memory, swap, disk, uptime_seconds, load_avg.
    """
    import time

    mem = psutil.virtual_memory()
    swap = psutil.swap_memory()
    disk = psutil.disk_usage("/")
    uptime_seconds = time.time() - psutil.boot_time()
    load_1, load_5, load_15 = os.getloadavg()

    return {
        "cpu_percent": psutil.cpu_percent(interval=0.5),
        "cpu_count": psutil.cpu_count(logical=True),
        "cpu_count_physical": psutil.cpu_count(logical=False),
        "memory": {
            "total_mb": round(mem.total / (1024 * 1024)),
            "available_mb": round(mem.available / (1024 * 1024)),
            "used_mb": round(mem.used / (1024 * 1024)),
            "percent": mem.percent,
        },
        "swap": {
            "total_mb": round(swap.total / (1024 * 1024)),
            "used_mb": round(swap.used / (1024 * 1024)),
            "percent": swap.percent,
        },
        "disk": {
            "total_gb": round(disk.total / (1024 ** 3), 1),
            "used_gb": round(disk.used / (1024 ** 3), 1),
            "free_gb": round(disk.free / (1024 ** 3), 1),
            "percent": disk.percent,
        },
        "uptime_seconds": round(uptime_seconds),
        "load_avg": {"1m": round(load_1, 2), "5m": round(load_5, 2), "15m": round(load_15, 2)},
    }


@mcp.tool(
    annotations={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    }
)
def get_top_processes(n: int = 10) -> dict[str, Any]:
    """
    Return the top N processes by CPU and memory usage.

    Args:
        n: Number of processes to return per category (default 10).

    Returns:
        Dict with 'by_cpu' and 'by_memory' lists.
    """
    processes: list[dict[str, Any]] = []
    for proc in psutil.process_iter(
        ["pid", "name", "cpu_percent", "memory_percent", "username"]
    ):
        try:
            info = proc.info
            processes.append(
                {
                    "pid": info["pid"],
                    "name": info["name"] or "",
                    "cpu_percent": round(info["cpu_percent"] or 0.0, 2),
                    "mem_percent": round(info["memory_percent"] or 0.0, 2),
                    "user": info["username"] or "",
                }
            )
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    by_cpu = sorted(processes, key=lambda x: x["cpu_percent"], reverse=True)[:n]
    by_mem = sorted(processes, key=lambda x: x["mem_percent"], reverse=True)[:n]

    return {"by_cpu": by_cpu, "by_memory": by_mem}


if __name__ == "__main__":
    mcp.run()