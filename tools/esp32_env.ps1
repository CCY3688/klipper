# Load this file with: . .\tools\esp32_env.ps1
# It prepares the project-local ESP-IDF and cartridge flashing commands.

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$IdfPath = Join-Path $RepoRoot '.tools\esp-idf-v4.4.7'
$EsptoolPath = Join-Path $RepoRoot '.tools\esptool-v3.3\esptool.py'
$IdfPython = Join-Path $RepoRoot '.tools\idf-python\Scripts\python.exe'

if (-not (Test-Path (Join-Path $IdfPath 'tools\idf.py'))) {
    throw "ESP-IDF 4.4.7 was not found at $IdfPath"
}

$env:IDF_PATH = $IdfPath
$env:IDF_TOOLS_PATH = Join-Path $env:USERPROFILE '.espressif'
if (-not $env:ESPPORT) { $env:ESPPORT = 'COM23' }
if (Test-Path $IdfPython) {
    $env:IDF_PYTHON_ENV_PATH = Split-Path -Parent (Split-Path -Parent $IdfPython)
    $Python = $IdfPython
    $env:PATH = "$(Split-Path -Parent $IdfPython);$env:PATH"
} else {
    $Python = 'python'
}

function idf.py { & $Python (Join-Path $env:IDF_PATH 'tools\idf.py') @args }
if (Test-Path $EsptoolPath) {
    function esptool.py { & $Python $EsptoolPath @args }
} else {
    function esptool.py { & $Python -m esptool @args }
}

# Load all installed Espressif tool paths when the IDF installer has completed.
# The wrapper functions above remain usable for chip probing before that step.
$IdfTools = Join-Path $env:IDF_TOOLS_PATH 'tools'
if (Test-Path $IdfTools) {
    . (Join-Path $env:IDF_PATH 'export.ps1')
}

Write-Host "ESP-IDF: $env:IDF_PATH"
Write-Host "ESP port: $env:ESPPORT"
Write-Host 'Commands available: idf.py, esptool.py'
