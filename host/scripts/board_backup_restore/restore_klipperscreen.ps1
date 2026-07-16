param(
    [string]$BoardHost = "192.168.67.182",
    [string]$BoardUser = "umeko",
    [string]$RemotePath = "/home/umeko/KlipperScreen",
    [string]$LocalBackup = "D:\ccy\Desktop\host\backups\board_192.168.67.182\20260620_klipperscreen_gui_backup\KlipperScreen",
    [string]$AskPass = "D:\ccy\Desktop\host\tools\ssh-askpass.bat"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $LocalBackup)) {
    throw "Backup path not found: $LocalBackup"
}

if (-not (Test-Path -LiteralPath $AskPass)) {
    throw "AskPass helper not found: $AskPass"
}

Write-Host "This will restore KlipperScreen from local backup to $BoardUser@$BoardHost`:$RemotePath"

$env:SSH_ASKPASS = $AskPass
$env:SSH_ASKPASS_REQUIRE = "force"
$env:DISPLAY = "dummy"

scp -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -r "$LocalBackup/." "${BoardUser}@${BoardHost}:${RemotePath}"

Write-Host "Restore complete."
