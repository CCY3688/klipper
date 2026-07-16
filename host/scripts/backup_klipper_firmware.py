"""Backup Klipper firmware and config from remote board via SSH + scp.
Uses SSH_ASKPASS helper for password-based auth.

Usage:
  python backup_klipper_firmware.py

Run from host/ directory. Output goes to:
  host/backups/board_192.168.67.182/<timestamp>/
"""

import os
import subprocess
import sys
from datetime import datetime

BOARD_HOST = "192.168.67.182"
BOARD_USER = "umeko"
ASKPASS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "tools", "ssh-askpass.bat")
BACKUP_ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "backups", f"board_{BOARD_HOST}")

REMOTE_PATHS = [
    "/home/umeko/klipper",               # Klipper firmware source
    "/home/umeko/moonraker",             # Moonraker
    "/home/umeko/printer_data/config",   # Printer configs
    "/home/umeko/printer_data/logs",     # Logs (recent only)
]

def run():
    print("=" * 60)
    print("Klipper Firmware Backup")
    print(f"  Board: {BOARD_USER}@{BOARD_HOST}")
    print(f"  Local: {BACKUP_ROOT}")
    print("=" * 60)

    env = os.environ.copy()
    env["SSH_ASKPASS"] = ASKPASS
    env["SSH_ASKPASS_REQUIRE"] = "force"
    env["DISPLAY"] = "dummy"

    ssh_opts = [
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "PreferredAuthentications=password",
        "-o", "PubkeyAuthentication=no",
    ]

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    dest = os.path.join(BACKUP_ROOT, f"{ts}_klipper_firmware_backup")
    os.makedirs(dest, exist_ok=True)

    # Step 1: capture remote snapshot
    print("\n[1/4] Capturing remote system info...")
    info_cmds = [
        "uname -a",
        "cat /etc/os-release",
        "klipper --version 2>/dev/null || echo 'klipper -v not available'",
    ]
    snapshot = os.path.join(dest, "meta_remote.txt")
    with open(snapshot, "w", encoding="utf-8") as f:
        f.write(f"date={datetime.now().isoformat()}\n")
        f.write(f"board={BOARD_USER}@{BOARD_HOST}\n\n")
        for cmd in info_cmds:
            f.write(f"--- $ {cmd} ---\n")
            try:
                result = subprocess.run(
                    ["ssh"] + ssh_opts + [f"{BOARD_USER}@{BOARD_HOST}", cmd],
                    env=env, capture_output=True, text=True, timeout=30
                )
                f.write(result.stdout)
                f.write(result.stderr)
            except Exception as e:
                f.write(f"ERROR: {e}\n")
            f.write("\n")
    print(f"  -> {snapshot}")

    # Step 2: scp the klipper firmware
    print("\n[2/4] Downloading klipper firmware...")
    for remote in REMOTE_PATHS:
        name = remote.replace("/", "_").strip("_")
        local_path = os.path.join(dest, name)
        print(f"  {remote} -> {local_path}")
        try:
            subprocess.run(
                ["scp"] + ssh_opts + ["-r",
                 f"{BOARD_USER}@{BOARD_HOST}:{remote}", local_path],
                env=env, check=False, timeout=300
            )
        except subprocess.TimeoutExpired:
            print(f"    WARNING: timeout on {remote}, skipping")

    # Step 3: list top-level home dir contents for reference
    print("\n[3/4] Listing remote home directory structure...")
    try:
        result = subprocess.run(
            ["ssh"] + ssh_opts + [f"{BOARD_USER}@{BOARD_HOST}",
             "ls -la /home/umeko/ && echo '---' && ls -la /home/umeko/printer_data/"],
            env=env, capture_output=True, text=True, timeout=30
        )
        listing_file = os.path.join(dest, "meta_home_listing.txt")
        with open(listing_file, "w", encoding="utf-8") as f:
            f.write(result.stdout)
        print(f"  -> {listing_file}")
    except Exception as e:
        print(f"  WARNING: {e}")

    # Step 4: summary
    print("\n[4/4] Backup complete!")
    print(f"\nBackup saved to: {dest}")
    print("Contents:")
    for item in sorted(os.listdir(dest)):
        full = os.path.join(dest, item)
        if os.path.isdir(full):
            count = sum(1 for _ in os.walk(full))
            print(f"  [{item}/] ({count} dirs)")
        else:
            size = os.path.getsize(full)
            print(f"  {item} ({size} bytes)")

if __name__ == "__main__":
    run()
