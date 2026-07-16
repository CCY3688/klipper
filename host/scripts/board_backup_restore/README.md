# Linux Board GUI Backup Notes

Board:
- Host: `192.168.67.182`
- User: `umeko`

Detected GUI-related directories on the board:
- `/home/umeko/KlipperScreen`
- `/home/umeko/fluidd`

Local backup root:
- `D:\ccy\Desktop\host\backups\board_192.168.67.182\20260620_klipperscreen_gui_backup`

Contents:
- `KlipperScreen/`: full copy of `/home/umeko/KlipperScreen`
- `fluidd/`: full copy of `/home/umeko/fluidd`
- `meta/remote_snapshot.txt`: remote state snapshot captured before any edits

Notes:
- `KlipperScreen` is a source repository and currently contains local modifications on the board.
- `fluidd` looks like a built frontend deployment directory rather than a source repository.
- Before restoring, review whether remote files changed after this backup was taken.

Helper files:
- `D:\ccy\Desktop\host\tools\ssh-askpass.bat`: returns the current SSH password for scripted access

Scripted restore:
- `scripts/board_backup_restore/restore_klipperscreen.ps1`
- `scripts/board_backup_restore/restore_fluidd.ps1`
