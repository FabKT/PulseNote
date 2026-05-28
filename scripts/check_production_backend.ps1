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

$base = $BackendBaseUrl.TrimEnd("/")
$headers = @{ "x-app-token" = $AppClientToken }

Write-Host "Health:"
Invoke-RestMethod -Uri "$base/health" -Method Get | ConvertTo-Json

Write-Host ""
Write-Host "OpenAI diagnostics:"
Invoke-RestMethod `
  -Uri "$base/diagnostics/openai" `
  -Method Get `
  -Headers $headers | ConvertTo-Json
