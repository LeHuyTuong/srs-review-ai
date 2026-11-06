# Launch the mobile web build on a FIXED port.
#
# Why this exists (2026-11-06): Google Sign-In on web checks the browser origin
# against the OAuth client's "Authorized JavaScript origins". The port is
# already fixed in web_dev_config.yaml (54614), so plain "flutter run" keeps the
# same origin. This script adds the other half: a PERSISTENT Chrome profile, so
# you do not have to sign in again on every launch.
#
# Run it from your own terminal (not in the background) when you want hot
# reload:
#     powershell -ExecutionPolicy Bypass -File tools\dev_web.ps1
param(
    [int]$Port = 54614
)

$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'

if (-not (Test-Path $chrome)) {
    throw "Chrome not found at $chrome. Edit `$chrome in this script."
}

# Open the browser only once the dev server is actually answering, so the tab
# does not land on a connection-refused page and sit there looking broken.
$waitThenOpen = @"
while (-not (Test-NetConnection -ComputerName localhost -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue)) { Start-Sleep -Milliseconds 500 }
Start-Process '$chrome' -ArgumentList '--no-first-run', '--no-default-browser-check', 'http://localhost:$Port'
"@
Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $waitThenOpen

Push-Location $appRoot
try {
    flutter run -d web-server --web-hostname localhost --web-port $Port
}
finally {
    Pop-Location
}
