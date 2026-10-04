param(
  [string]$BaseUrl = "http://127.0.0.1:8787"
)

$ErrorActionPreference = "Stop"

# La route /diagnostics/openai a ete retiree (elle consommait l'API OpenAI
# sans controle d'abonnement). On verifie la sante du service et que les
# routes IA refusent bien un appel non authentifie.
Write-Host "Backend: $BaseUrl"
Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get | ConvertTo-Json

try {
  Invoke-RestMethod -Uri "$BaseUrl/summarize" -Method Post `
    -ContentType "application/json" -Body '{"text":"test"}' | Out-Null
  throw "/summarize a repondu sans authentification : configuration dangereuse."
} catch [System.Net.WebException] {
  Write-Host "OK : /summarize refuse les appels non authentifies."
}
