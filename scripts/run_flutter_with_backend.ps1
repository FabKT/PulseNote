param(
  [string]$BackendBaseUrl,

  [string]$SupabaseUrl,

  [string]$SupabaseAnonKey,

  [string]$GoogleWebClientId
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

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

  $BackendBaseUrl = "http://${ip}:8787"
}

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

Write-Host "Backend utilise par l'app: $BackendBaseUrl"

$defines = @(
  "--dart-define=BACKEND_BASE_URL=$BackendBaseUrl",
  "--dart-define=SUPABASE_URL=$SupabaseUrl",
  "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey"
)
if (![string]::IsNullOrWhiteSpace($GoogleWebClientId)) {
  $defines += "--dart-define=GOOGLE_WEB_CLIENT_ID=$GoogleWebClientId"
}

& flutter run @defines
