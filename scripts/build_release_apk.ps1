param(
  [Parameter(Mandatory = $true)]
  [string]$BackendBaseUrl,

  [string]$AppClientToken
)

$ErrorActionPreference = "Stop"

Set-Location "C:\dev1\audio_recorder_app"

if ([string]::IsNullOrWhiteSpace($AppClientToken)) {
  $envPath = "C:\dev1\audio_recorder_app\backend\.env"
  if (!(Test-Path $envPath)) {
    throw "backend\.env introuvable. Precise -AppClientToken manuellement."
  }

  $line = Get-Content $envPath |
    Where-Object { $_ -match "^APP_CLIENT_TOKEN=" } |
    Select-Object -First 1

  if ([string]::IsNullOrWhiteSpace($line)) {
    throw "APP_CLIENT_TOKEN introuvable dans backend\.env."
  }

  $AppClientToken = $line.Substring("APP_CLIENT_TOKEN=".Length).Trim()
}

& "C:\dev1\Flutter\flutter\bin\flutter.bat" build apk --release `
  "--dart-define=BACKEND_BASE_URL=$BackendBaseUrl" `
  "--dart-define=APP_CLIENT_TOKEN=$AppClientToken"
