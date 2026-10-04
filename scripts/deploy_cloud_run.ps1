param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectId,

  [string]$Region = "europe-west1",

  [string]$ServiceName = "pulsenote-api",

  [string]$OpenAiApiKey,

  [string]$SupabaseServiceRoleKey,

  [string]$SupabaseUrl,

  [string]$SupabaseAnonKey
)

$ErrorActionPreference = "Stop"

Set-Location (Split-Path -Parent $PSScriptRoot)

function Require-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "$name est introuvable. Installe-le avant de relancer ce script."
  }
}

function Read-EnvValue($key) {
  $envPath = Join-Path (Split-Path -Parent $PSScriptRoot) "backend\.env"
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

if ([string]::IsNullOrWhiteSpace($SupabaseServiceRoleKey)) {
  $SupabaseServiceRoleKey = Read-EnvValue "SUPABASE_SERVICE_ROLE_KEY"
}

if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
  $SupabaseUrl = Read-EnvValue "SUPABASE_URL"
}

if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
  $SupabaseAnonKey = Read-EnvValue "SUPABASE_ANON_KEY"
}

if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
  throw "SUPABASE_URL et SUPABASE_ANON_KEY sont requis (backend\.env ou parametres -SupabaseUrl/-SupabaseAnonKey)."
}

gcloud config set project $ProjectId

gcloud services enable `
  run.googleapis.com `
  cloudbuild.googleapis.com `
  artifactregistry.googleapis.com `
  secretmanager.googleapis.com `
  --project $ProjectId

Ensure-Secret "pulsenote-openai-api-key" $OpenAiApiKey
Ensure-Secret "pulsenote-supabase-service-role-key" $SupabaseServiceRoleKey

gcloud run deploy $ServiceName `
  --project $ProjectId `
  --region $Region `
  --source "backend" `
  --allow-unauthenticated `
  --set-env-vars "TRANSCRIPTION_MODEL=gpt-4o-transcribe,REALTIME_TRANSCRIPTION_MODEL=gpt-realtime-whisper,SUMMARY_MODEL=gpt-4.1-mini,DEFAULT_LANGUAGE=fr,SUPABASE_URL=$SupabaseUrl,SUPABASE_ANON_KEY=$SupabaseAnonKey" `
  --set-secrets "OPENAI_API_KEY=pulsenote-openai-api-key:latest,SUPABASE_SERVICE_ROLE_KEY=pulsenote-supabase-service-role-key:latest"

$url = gcloud run services describe $ServiceName `
  --project $ProjectId `
  --region $Region `
  --format "value(status.url)"

Write-Host ""
Write-Host "Backend production deploye : $url"
Write-Host ""
Write-Host "Commande de build Flutter production :"
Write-Host ".\scripts\build_release_apk.ps1 -BackendBaseUrl `"$url`""
