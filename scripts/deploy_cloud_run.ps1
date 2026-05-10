param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectId,

  [string]$Region = "europe-west1",

  [string]$ServiceName = "pulsenote-api",

  [string]$OpenAiApiKey,

  [string]$AppClientToken
)

$ErrorActionPreference = "Stop"

Set-Location "C:\dev1\audio_recorder_app"

function Require-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "$name est introuvable. Installe-le avant de relancer ce script."
  }
}

function Read-EnvValue($key) {
  $envPath = "C:\dev1\audio_recorder_app\backend\.env"
  if (!(Test-Path $envPath)) { return "" }
  $line = Get-Content $envPath |
    Where-Object { $_ -match "^$key=" } |
    Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($line)) { return "" }
  return $line.Substring($key.Length + 1).Trim()
}

function Ensure-Secret($name, $value) {
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Valeur manquante pour le secret $name."
  }

  $exists = $true
  gcloud secrets describe $name --project $ProjectId *> $null
  if ($LASTEXITCODE -ne 0) { $exists = $false }

  if (-not $exists) {
    gcloud secrets create $name `
      --project $ProjectId `
      --replication-policy automatic
  }

  $value | gcloud secrets versions add $name `
    --project $ProjectId `
    --data-file=-
}

Require-Command "gcloud"

if ([string]::IsNullOrWhiteSpace($OpenAiApiKey)) {
  $OpenAiApiKey = Read-EnvValue "OPENAI_API_KEY"
}

if ([string]::IsNullOrWhiteSpace($AppClientToken)) {
  $AppClientToken = Read-EnvValue "APP_CLIENT_TOKEN"
}

gcloud config set project $ProjectId

gcloud services enable `
  run.googleapis.com `
  cloudbuild.googleapis.com `
  artifactregistry.googleapis.com `
  secretmanager.googleapis.com `
  --project $ProjectId

Ensure-Secret "pulsenote-openai-api-key" $OpenAiApiKey
Ensure-Secret "pulsenote-app-client-token" $AppClientToken

gcloud run deploy $ServiceName `
  --project $ProjectId `
  --region $Region `
  --source "backend" `
  --allow-unauthenticated `
  --set-env-vars "TRANSCRIPTION_MODEL=gpt-4o-transcribe,REALTIME_TRANSCRIPTION_MODEL=gpt-realtime-whisper,SUMMARY_MODEL=gpt-4.1-mini,DEFAULT_LANGUAGE=fr" `
  --set-secrets "OPENAI_API_KEY=pulsenote-openai-api-key:latest,APP_CLIENT_TOKEN=pulsenote-app-client-token:latest"

$url = gcloud run services describe $ServiceName `
  --project $ProjectId `
  --region $Region `
  --format "value(status.url)"

Write-Host ""
Write-Host "Backend production deploye : $url"
Write-Host ""
Write-Host "Commande de build Flutter production :"
Write-Host ".\scripts\build_release_apk.ps1 -BackendBaseUrl `"$url`""
