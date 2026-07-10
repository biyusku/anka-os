"""
ActionConfirmationGate — pre-action confirmation and snapshotting.

Intercepts destructive AI-initiated actions and:
  1. Checks whether confirmation is required (pattern-based).
  2. Presents a KDE kdialog prompt to the user.
  3. Optionally creates a snapper snapshot before proceeding.

GhostApproval mitigation: all paths are resolved through os.path.realpath()
before pattern matching — symlink traversal cannot bypass approval rules.
"""

from __future__ import annotations

import logging
import os
import subprocess
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

log = logging.getLogger("anka.confirmation_gate")

# ---------------------------------------------------------------------------
# Destructive action patterns
# ---------------------------------------------------------------------------

# Each entry: (description, substring_or_prefix_patterns_list)
DESTRUCTIVE_PATTERNS: list[tuple[str, list[str]]] = [
    ("File deletion", ["delete_file", "rm ", "unlink", "shutil.rmtree"]),
    ("Package modification", ["install_package", "remove_package", "update_system", "nixos-rebuild"]),
    ("Service restart/stop", ["restart_service", "stop_service", "systemctl restart", "systemctl stop"]),
    ("Process termination", ["kill_process", "SIGKILL", "SIGTERM"]),
    ("Network disconnect", ["disconnect_network", "nmcli networking off"]),
    ("System shutdown/reboot", ["schedule_shutdown", "shutdown", "reboot", "poweroff"]),
    ("Bulk file write", ["write_file", "overwrite", "truncate"]),
    ("Database modification", ["DROP TABLE", "DELETE FROM", "TRUNCATE"]),
    ("Permission change", ["chmod", "chown", "setuid"]),
    ("Hostname/timezone change", ["set_hostname", "set_timezone", "hostnamectl"]),
]

# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------


@dataclass
class ActionContext:
    tool_name: str
    arguments: dict
    description: str = ""
    resolved_path: Optional[str] = None  # real path after symlink resolution


# ---------------------------------------------------------------------------
# Gate
# ---------------------------------------------------------------------------


class ActionConfirmationGate:
    """Evaluate whether a proposed action needs confirmation and handle it."""

    # ------------------------------------------------------------------
    # Pattern matching
    # ------------------------------------------------------------------

    def needs_confirmation(self, action: ActionContext) -> bool:
        """
        Return True if the action matches any destructive pattern.

        Path arguments are resolved to real paths before matching to prevent
        symlink-based approval bypass (GhostApproval attack vector).
        """
        probe = (action.tool_name + " " + str(action.arguments)).lower()

        # Resolve any path-like values in arguments
        resolved_probes: list[str] = [probe]
        for v in action.arguments.values():
            if isinstance(v, str) and ("/" in v or "\\" in v):
                try:
                    real = os.path.realpath(v)
                    resolved_probes.append(real.lower())
                except Exception:
                    pass

        for _desc, patterns in DESTRUCTIVE_PATTERNS:
            for pat in patterns:
                if any(pat.lower() in p for p in resolved_probes):
                    return True

        return False

    # ------------------------------------------------------------------
    # User confirmation dialog
    # ------------------------------------------------------------------

    def build_confirmation_message(self, action: ActionContext) -> str:
        """Build a human-readable confirmation prompt."""
        lines = [
            "ANKA AI is about to perform a potentially destructive action.",
            "",
            f"Action:  {action.tool_name}",
        ]
        if action.description:
            lines.append(f"Details: {action.description}")
        if action.arguments:
            for k, v in action.arguments.items():
                lines.append(f"  {k}: {v}")
        if action.resolved_path:
            lines.append(f"Path (resolved): {action.resolved_path}")
        lines += ["", "Do you want to proceed?"]
        return "\n".join(lines)

    def request_user_confirmation(self, action: ActionContext) -> bool:
        """
        Show a KDE kdialog prompt and return True if the user confirmed.

        Falls back to terminal stdin confirmation if kdialog is unavailable
        (e.g., headless sessions or SSH).
        """
        message = self.build_confirmation_message(action)
        title = f"Confirm: {action.tool_name}"

        # Try kdialog first (KDE Plasma native)
        try:
            result = subprocess.run(
                ["kdialog", "--yesno", message, "--title", title],
                timeout=120,  # 2-minute user decision window
            )
            confirmed = result.returncode == 0
            log.info(
                "Confirmation dialog result",
                extra={"action": action.tool_name, "confirmed": confirmed, "method": "kdialog"},
            )
            return confirmed
        except FileNotFoundError:
            pass
        except subprocess.TimeoutExpired:
            log.warning("Confirmation dialog timed out — denying")
            return False

        # Fallback: zenity (GNOME / GTK)
        try:
            result = subprocess.run(
                [
                    "zenity",
                    "--question",
                    f"--text={message}",
                    f"--title={title}",
                    "--width=500",
                ],
                timeout=120,
            )
            confirmed = result.returncode == 0
            log.info(
                "Confirmation dialog result",
                extra={"action": action.tool_name, "confirmed": confirmed, "method": "zenity"},
            )
            return confirmed
        except FileNotFoundError:
            pass
        except subprocess.TimeoutExpired:
            return False

        # Last resort: headless rejection (safe default)
        log.warning(
            "No confirmation UI available — denying destructive action",
            extra={"action": action.tool_name},
        )
        return False

    # ------------------------------------------------------------------
    # Pre-action snapshot
    # ------------------------------------------------------------------

    def create_snapshot_before_action(
        self, description: str = "anka-ai pre-action"
    ) -> Optional[str]:
        """
        Create a system snapshot before a destructive action.

        Tries snapper first (Btrfs/LVM), then git stash for the current
        working directory as a lighter-weight alternative.

        Returns:
            Snapshot identifier string, or None if no snapshot was created.
        """
        # Try snapper (Btrfs)
        try:
            result = subprocess.run(
                ["snapper", "create", "--description", description, "--print-number"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode == 0:
                snap_id = result.stdout.strip()
                log.info("Snapper snapshot created", extra={"id": snap_id, "desc": description})
                return f"snapper:{snap_id}"
        except FileNotFoundError:
            pass
        except Exception:
            log.debug("Snapper failed", extra={"err": traceback.format_exc()})

        # Fallback: git stash in current directory
        try:
            cwd = Path.cwd()
            if (cwd / ".git").exists():
                result = subprocess.run(
                    ["git", "stash", "push", "-m", description],
                    capture_output=True,
                    text=True,
                    cwd=str(cwd),
                    timeout=15,
                )
                if result.returncode == 0:
                    log.info("Git stash created", extra={"path": str(cwd)})
                    return f"git-stash:{cwd}"
        except Exception:
            log.debug("Git stash failed", extra={"err": traceback.format_exc()})

        return None

    # ------------------------------------------------------------------
    # Full gate pipeline
    # ------------------------------------------------------------------

    def gate(self, action: ActionContext) -> bool:
        """
        Full gate pipeline:
        1. Check if confirmation is needed.
        2. If yes, resolve paths and request confirmation.
        3. If confirmed, attempt pre-action snapshot.
        4. Return True to proceed, False to abort.
        """
        if not self.needs_confirmation(action):
            return True

        # Resolve path argument if present
        for k, v in action.arguments.items():
            if isinstance(v, str) and ("/" in v or "\\" in v):
                try:
                    action.resolved_path = os.path.realpath(v)
                except Exception:
                    pass
                break

        confirmed = self.request_user_confirmation(action)
        if not confirmed:
            log.info(
                "Action denied by user", extra={"tool": action.tool_name}
            )
            return False

        # Optional pre-action snapshot
        snap = self.create_snapshot_before_action(
            description=f"before {action.tool_name}"
        )
        if snap:
            log.info("Pre-action snapshot", extra={"snapshot": snap})

        return True