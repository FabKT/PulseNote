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

### Manga page generation

```http
POST /api/manga/generate-page
Content-Type: application/json
```

Body minimal :

```json
{
  "operation": "generate",
  "prompt": "Vertical black-and-white manga page with 6 readable panels...",
  "panelCount": 6,
  "selectedAssets": []
}
```

Réponse :

```json
{
  "imageDataUrl": "data:image/png;base64,...",
  "imageUrl": "data:image/png;base64,...",
  "model": "gpt-image-2",
  "creditsUsed": 10
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

## Reprise des generations de texte

Les clients compatibles utilisent `GET /api/text/capabilities`, puis
`POST /api/text/jobs` avec un UUID `requestId`. La reponse 202 est immediate.
`GET /api/text/jobs/:requestId` suit la meme reponse OpenAI en background.
`POST /api/text/jobs/:requestId/cancel` demande son annulation. Toutes ces routes
gardent le middleware d'authentification existant; aucun appel de generation ne
doit etre repete automatiquement apres une reponse reseau incertaine.

Le client conserve le ticket signe retourne par le suivi et le renvoie dans
`x-text-job-ticket`. Avec ce ticket et le meme secret applicatif, le suivi peut
reprendre apres un redemarrage du backend sans recreer de reponse OpenAI.
Avant reception de l'identifiant fournisseur/ticket, une perte du registre en
memoire reste non recuperable: le client signale l'incertitude, il ne resoumet pas.
La deduplication des POST est en memoire, pas une garantie durable multi-instance.
Un worker et un registre persistant restent necessaires pour cette garantie.

L'ancien `POST /api/text/complete` reste compatible. `TEXT_TIMEOUT_MS=0` ou absent
supprime sa limite totale applicative. Les requetes du nouveau protocole ont une
limite reseau individuelle de 90 secondes, pas une limite de duree de generation.
L'annulation n'est pas une garantie de remboursement du travail deja accepte.
Aucune nouvelle cle ni variable secrete n'est necessaire.

Tests sans appel fournisseur payant:
`node --test src/text-jobs.test.js src/text-job-routes.test.js src/text-timeout.test.js`.

## Claude and Meshy via fal.ai

Text jobs accept `provider: "gpt"` (default) or `provider: "claude"`.
Configure `CLAUDE_API_KEY` or `ANTHROPIC_API_KEY`; `CLAUDE_MODEL` defaults to
`claude-sonnet-5-5`. Multi-workspace keys additionally require
`ANTHROPIC_WORKSPACE_ID`. These are Console API credentials, not a Claude Code
OAuth session. Unsupported/unavailable providers never silently fall back to GPT.
Claude results use the same signed tickets and normalized usage format. Messages
are streamed server-side and polled through short client requests. Finished results
are retained for 24 hours in `CLAUDE_JOB_DIR` (temporary directory by default).
A persistent Render disk is required to keep them across deployments. Running
Messages cannot be resumed after process restart and are never resubmitted.

Configure `FALAI_API_KEY`, `FAL_KEY` or `FAL_API_KEY` for Meshy v6. Authenticated
`GET /api/3d/capabilities`, `POST /api/3d/jobs`,
`GET /api/3d/jobs/:requestId` and `POST /api/3d/jobs/:requestId/cancel` implement
full textured generation, image reconstruction, humanoid rigging and basic
animations. Use an application UUID on submission and return the signed ticket in
`x-3d-job-ticket` for polling/cancellation. Only fixed Meshy endpoints are allowed;
provider credentials are never forwarded to returned media URLs or foreign hosts.
Submission deduplication is process-local (24h), not a multi-instance guarantee.
Cancellation cannot refund already accepted provider work.

Tests without provider charges:
`node --test src/claude-provider.test.js src/fal-meshy.test.js src/text-jobs.test.js src/text-job-routes.test.js src/text-timeout.test.js`.
