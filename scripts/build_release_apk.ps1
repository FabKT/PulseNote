param(
  [Parameter(Mandatory = $true)]
  [string]$BackendBaseUrl,

  [string]$SupabaseUrl,

  [string]$SupabaseAnonKey,

  [string]$GoogleWebClientId
)

$ErrorActionPreference = "Stop"

# Racine du projet = dossier parent de scripts\, quel que soit l'emplacement
# du depot sur le disque.
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Read-BackendEnvValue($key) {
  $envPath = Join-Path $ProjectRoot "backend\.env"
  if (!(Test-Path $envPath)) { return "" }
  $line = Get-Content $envPath |
    Where-Object { $_ -match "^$key=" } |
    Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($line)) { return "" }
  return $line.Substring($key.Length + 1).Trim()
}

if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
  $SupabaseUrl = Read-BackendEnvValue "SUPABASE_URL"
}
if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
  $SupabaseAnonKey = Read-BackendEnvValue "SUPABASE_ANON_KEY"
}
if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
  throw "SUPABASE_URL / SUPABASE_ANON_KEY introuvables. Precise -SupabaseUrl et -SupabaseAnonKey."
}

if (!(Test-Path (Join-Path $ProjectRoot "android\key.properties"))) {
  throw "android\key.properties introuvable : le bundle serait signe avec la cle debug."
}

$defines = @(
  "--dart-define=BACKEND_BASE_URL=$BackendBaseUrl",
  "--dart-define=SUPABASE_URL=$SupabaseUrl",
  "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey"
)
if (![string]::IsNullOrWhiteSpace($GoogleWebClientId)) {
  $defines += "--dart-define=GOOGLE_WEB_CLIENT_ID=$GoogleWebClientId"
}

# Google Play exige un Android App Bundle (.aab) pour toute soumission de
# production depuis 2021 - un .apk seul est refuse a l'upload sur la Play
# Console. On construit donc un bundle, pas un APK.
& flutter build appbundle --release @defines
if ($LASTEXITCODE -ne 0) { throw "flutter build appbundle a echoue." }

Write-Host ""
Write-Host "Bundle genere : build\app\outputs\bundle\release\app-release.aab"
