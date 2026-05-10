param(
  [string]$BaseUrl = "http://127.0.0.1:8787"
)

$ErrorActionPreference = "Stop"

Write-Host "Backend: $BaseUrl"
$health = Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get
$health | ConvertTo-Json

Write-Host ""
Write-Host "Si ok=true apparait, le backend repond correctement."
