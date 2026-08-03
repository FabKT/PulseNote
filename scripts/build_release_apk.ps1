param(
  [Parameter(Mandatory = $true)]
  [string]$BackendBaseUrl,

  [string]$AppClientToken,

  [Parameter(Mandatory = $true)]
  [string]$SupabaseUrl,

  [Parameter(Mandatory = $true)]
  [string]$SupabaseAnonKey,

  [string]$GoogleWebClientId
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

# Google Play exige un Android App Bundle (.aab) pour toute soumission de
# production depuis 2021 - un .apk seul est refuse a l'upload sur la Play
# Console. On construit donc un bundle, pas un APK.
& "C:\dev1\Flutter\flutter\bin\flutter.bat" build appbundle --release `
  "--dart-define=BACKEND_BASE_URL=$BackendBaseUrl" `
  "--dart-define=APP_CLIENT_TOKEN=$AppClientToken" `
  "--dart-define=SUPABASE_URL=$SupabaseUrl" `
  "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey" `
  "--dart-define=GOOGLE_WEB_CLIENT_ID=$GoogleWebClientId"

Write-Host ""
Write-Host "Bundle genere : build\app\outputs\bundle\release\app-release.aab"
