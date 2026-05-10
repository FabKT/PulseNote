# Ultimate Audio Recorder - Deploiement production

Cette configuration de production garde la cle OpenAI uniquement cote backend.
L'application Flutter ne contient que l'URL HTTPS du backend et un token
app temporaire.

## Choix technique

- Backend : Node.js / Express deploye sur Google Cloud Run.
- Secrets : Google Secret Manager.
- IA : OpenAI appele uniquement depuis le backend.
- Mobile : Flutter Android avec `BACKEND_BASE_URL` injecte au build.

## Prerequis

1. Un compte Google Cloud avec facturation active.
2. Google Cloud CLI installe : `gcloud`.
3. Un projet Google Cloud, par exemple `pulsenote-prod`.
4. Une cle OpenAI valide.
5. `backend\.env` rempli localement pour que les scripts puissent lire :
   - `OPENAI_API_KEY`
   - `APP_CLIENT_TOKEN`

## Deployer le backend

Depuis `C:\dev1\audio_recorder_app` :

```powershell
.\scripts\deploy_cloud_run.ps1 -ProjectId "TON_PROJECT_ID"
```

Le script :

- active les APIs Google necessaires ;
- cree les secrets `pulsenote-openai-api-key` et `pulsenote-app-client-token` ;
- deploie le backend sur Cloud Run ;
- affiche l'URL HTTPS de production.

## Verifier le backend production

```powershell
.\scripts\check_production_backend.ps1 -BackendBaseUrl "https://TON-SERVICE.a.run.app"
```

Le test doit afficher `ok: true` pour `/health` et pour
`/diagnostics/openai`.

## Builder l'APK production

```powershell
.\scripts\build_release_apk.ps1 -BackendBaseUrl "https://TON-SERVICE.a.run.app"
```

L'APK sera genere ici :

```text
build\app\outputs\flutter-apk\app-release.apk
```

## Important avant publication

Le token `APP_CLIENT_TOKEN` est une protection temporaire. Pour une vraie
publication, il faudra remplacer ce token statique par une authentification
utilisateur, idealement Firebase Auth, puis verifier les abonnements cote
backend.
