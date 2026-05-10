$ErrorActionPreference = "Stop"

Set-Location "C:\dev1\audio_recorder_app\backend"

if (!(Test-Path ".env")) {
  throw "backend\.env est introuvable."
}

$envLines = Get-Content ".env"
if (-not ($envLines | Where-Object { $_ -match "^REALTIME_TRANSCRIPTION_MODEL=" })) {
  Add-Content ".env" "REALTIME_TRANSCRIPTION_MODEL=gpt-realtime-whisper"
}

npm run dev
