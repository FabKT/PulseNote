# Ultimate Audio Recorder Backend

Backend sécurisé pour :

- transcription d'un fichier audio enregistré,
- résumé IA,
- création d'une session éphémère pour transcription instantanée Realtime.

La clé OpenAI reste ici, jamais dans l'application Flutter.

## Installation locale

```powershell
cd C:\dev1\audio_recorder_app\backend
npm install
Copy-Item .env.example .env
```

Ensuite ouvre `.env` et remplace :

```env
OPENAI_API_KEY=ta_cle_openai
APP_CLIENT_TOKEN=un_long_secret_aleatoire
```

Pour générer un secret :

```powershell
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

## Lancer le backend

```powershell
npm run dev
```

Test santé :

```powershell
curl.exe http://localhost:8787/health
```

## Endpoints

Tous les endpoints protégés demandent l'en-tête :

```text
x-app-token: APP_CLIENT_TOKEN
```

### Transcription fichier

```http
POST /transcribe
Content-Type: multipart/form-data
Field: audio
```

Réponse :

```json
{
  "text": "Transcription...",
  "model": "gpt-4o-transcribe"
}
```

### Résumé

```http
POST /summarize
Content-Type: application/json
```

Body :

```json
{
  "text": "Texte à résumer"
}
```

Réponse :

```json
{
  "summary": "Résumé...",
  "model": "gpt-4.1-mini"
}
```

### Session transcription instantanée

```http
POST /realtime/transcription-session
```

Réponse : objet de session OpenAI contenant un `client_secret` éphémère.

## Déploiement recommandé

Options simples :

- Render
- Railway
- Fly.io
- Google Cloud Run

Le backend doit être accessible en HTTPS pour l'application mobile.
