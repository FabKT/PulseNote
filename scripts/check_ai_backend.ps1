param(
  [string]$BaseUrl = "http://127.0.0.1:8787",

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

Write-Host "Backend: $BaseUrl"
$health = Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get
$health | ConvertTo-Json

Write-Host ""
Write-Host "OpenAI diagnostics:"
$headers = @{ "x-app-token" = $AppClientToken }
$diagnostics = Invoke-RestMethod `
  -Uri "$BaseUrl/diagnostics/openai" `
  -Method Get `
  -Headers $headers
$diagnostics | ConvertTo-Json

Write-Host ""
Write-Host "Si ok=true apparait deux fois, le token app et la cle OpenAI sont acceptes."
