param(
  [string]$BackendBaseUrl,

  [string]$AppClientToken
)

$ErrorActionPreference = "Stop"

Set-Location "C:\dev1\audio_recorder_app"

if ([string]::IsNullOrWhiteSpace($BackendBaseUrl)) {
  $ip = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
      $_.IPAddress -notlike "127.*" -and
      $_.PrefixOrigin -ne "WellKnown" -and
      $_.InterfaceAlias -notmatch "Loopback|vEthernet|Virtual|VMware|Bluetooth"
    } |
    Select-Object -First 1 -ExpandProperty IPAddress

  if ([string]::IsNullOrWhiteSpace($ip)) {
    throw "Impossible de detecter l'IP locale. Precise -BackendBaseUrl manuellement."
  }

  $BackendBaseUrl = "http://$ip:8787"
}

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

Write-Host "Backend utilise par l'app: $BackendBaseUrl"
Write-Host "Token app: charge depuis backend\.env"

& "C:\dev1\Flutter\flutter\bin\flutter.bat" run `
  "--dart-define=BACKEND_BASE_URL=$BackendBaseUrl" `
  "--dart-define=APP_CLIENT_TOKEN=$AppClientToken"
