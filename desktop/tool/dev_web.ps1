# Launch the web build with a PERSISTENT browser profile.
#
# Why this exists (2026-09-25): `flutter run -d chrome` creates a throwaway
# Chrome profile in %TEMP%\flutter_tools.<hash>\... on EVERY run. On web the
# review history lives in IndexedDB, so every relaunch started the app with an
# empty history — the sessions were still on disk in the previous profile, but
# the app had no idea. That is how a real history "disappeared".
#
# This script fixes both halves that have to agree:
#   * a FIXED port (54613) and a FIXED profile (%LOCALAPPDATA%\srs-review-ai\
#     chrome-profile), so the browser origin and its IndexedDB stay the same;
#   * `flutter run` stays in the foreground, so `r` / `R` hot reload still work.
#
# Run it from your own terminal (not in the background) when you want hot
# reload:
#     powershell -ExecutionPolicy Bypass -File app\tool\dev_web.ps1
param(
    [int]$Port = 54613
)

$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
$profile = Join-Path $env:LOCALAPPDATA 'srs-review-ai\chrome-profile'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'

if (-not (Test-Path $chrome)) {
    throw "Chrome not found at $chrome. Edit `$chrome in this script."
}

New-Item -ItemType Directory -Force -Path $profile | Out-Null

# Open the browser only once the dev server is actually answering, so the tab
# does not land on a connection-refused page and sit there looking broken.
$waitThenOpen = @"
while (-not (Test-NetConnection -ComputerName localhost -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue)) { Start-Sleep -Milliseconds 500 }
Start-Process '$chrome' -ArgumentList '--user-data-dir=$profile', '--no-first-run', '--no-default-browser-check', 'http://localhost:$Port'
"@
Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $waitThenOpen

Push-Location $appRoot
try {
    flutter run -d web-server --web-hostname localhost --web-port $Port
}
finally {
    Pop-Location
}