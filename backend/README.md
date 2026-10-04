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
SUPABASE_URL=https://ton-projet.supabase.co
SUPABASE_ANON_KEY=ta_cle_anon
SUPABASE_SERVICE_ROLE_KEY=ta_cle_service_role
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

Tous les endpoints protégés demandent le jeton de session Supabase de
l'utilisateur :

```text
Authorization: Bearer <access_token Supabase>
```

Il n'existe plus de jeton applicatif partagé : un secret embarqué dans l'APK
est extractible. `/transcribe`, `/summarize` et
`/realtime/transcription-session` exigent en plus un abonnement Pro actif et
sont limités à 60 appels par heure et par utilisateur.

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

Réponse : objet de session OpenAI contenant un `client_secret` éphémère
(valable 10 minutes). Débite 10 crédits IA, remboursés si la session ne peut
pas être créée.

## Déploiement recommandé

Options simples :

- Render
- Railway
- Fly.io
- Google Cloud Run

Le backend doit être accessible en HTTPS pour l'application mobile.
