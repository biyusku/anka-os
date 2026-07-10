#!/usr/bin/env python3
"""
ANKA OS KDE Update Notifier
Sends KDE plasma notifications for system updates
"""

import subprocess
import sys
import json
import os
import logging
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/anka/update-notifier.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('anka-notifier')


def send_kde_notification(
    title: str,
    message: str,
    icon: str = "system-software-update",
    urgency: str = "normal",
    actions: list[dict] | None = None
) -> bool:
    """Send a KDE plasma notification via notify-send or kdialog."""
    try:
        # Try notify-send first (works with any notification daemon)
        cmd = [
            'notify-send',
            '--app-name=ANKA Update',
            f'--icon={icon}',
            f'--urgency={urgency}',
            title,
            message
        ]

        if actions:
            # notify-send doesn't support actions well, use kdialog for that
            pass

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10,
            env={**os.environ, 'DISPLAY': ':0', 'DBUS_SESSION_BUS_ADDRESS': get_dbus_session()}
        )

        if result.returncode == 0:
            logger.info(f"Notification sent: {title}")
            return True

    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        logger.warning(f"notify-send failed: {e}")

    try:
        # Fallback to kdialog
        subprocess.run(
            ['kdialog', '--title', f'ANKA: {title}', '--msgbox', message],
            timeout=30,
            env={**os.environ, 'DISPLAY': ':0'}
        )
        return True
    except Exception as e:
        logger.error(f"kdialog also failed: {e}")
        return False


def get_dbus_session() -> str:
    """Get the D-Bus session bus address for the current user."""
    # Try to find DBUS_SESSION_BUS_ADDRESS from running processes
    try:
        result = subprocess.run(
            ['pgrep', '-u', 'anka', '-x', 'plasmashell'],
            capture_output=True, text=True
        )
        if result.stdout.strip():
            pid = result.stdout.strip().split('\n')[0]
            with open(f'/proc/{pid}/environ', 'rb') as f:
                env_data = f.read().decode('utf-8', errors='replace')
                for entry in env_data.split('\x00'):
                    if entry.startswith('DBUS_SESSION_BUS_ADDRESS='):
                        return entry.split('=', 1)[1]
    except Exception:
        pass

    return os.environ.get('DBUS_SESSION_BUS_ADDRESS', '')


def notify_update_available(version_info: dict) -> None:
    """Notify user that ANKA updates are available."""
    current = version_info.get('current', 'unknown')
    available = version_info.get('available', 'unknown')
    changes = version_info.get('changes', [])

    title = "ANKA Update Available"
    message = f"ANKA {available} is ready to install (current: {current})"

    if changes:
        message += "\n\nChanges:\n" + "\n".join(f"• {c}" for c in changes[:5])

    send_kde_notification(
        title=title,
        message=message,
        icon="system-software-update",
        urgency="normal"
    )


def notify_update_complete(version: str) -> None:
    """Notify user that update completed successfully."""
    send_kde_notification(
        title="ANKA Updated Successfully",
        message=f"ANKA has been updated to version {version}. Please restart to apply changes.",
        icon="dialog-ok",
        urgency="normal"
    )


def notify_update_failed(error: str) -> None:
    """Notify user that update failed."""
    send_kde_notification(
        title="ANKA Update Failed",
        message=f"Update failed: {error[:200]}",
        icon="dialog-error",
        urgency="critical"
    )


def main() -> None:
    """Main entry point for ANKA update notifier."""
    if len(sys.argv) < 2:
        print("Usage: kde-notifier.py <action> [data]")
        print("Actions: available, complete, failed")
        sys.exit(1)

    action = sys.argv[1]

    if action == "available" and len(sys.argv) > 2:
        try:
            version_info = json.loads(sys.argv[2])
            notify_update_available(version_info)
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON: {e}")
            sys.exit(1)

    elif action == "complete" and len(sys.argv) > 2:
        notify_update_complete(sys.argv[2])

    elif action == "failed" and len(sys.argv) > 2:
        notify_update_failed(sys.argv[2])

    else:
        logger.error(f"Unknown action: {action}")
        sys.exit(1)


if __name__ == "__main__":
    main()