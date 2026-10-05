# Ultimate Audio Recorder - Deploiement production

Cette configuration de production garde la cle OpenAI uniquement cote backend.
L'application Flutter ne contient que l'URL HTTPS du backend et la cle
publique (anon) Supabase ; chaque appel est authentifie par la session
Supabase de l'utilisateur.

## Choix technique

- Backend : Node.js / Express deploye sur Render ou Google Cloud Run.
- Secrets : variables secretes de l'hebergeur (Render) ou Google Secret Manager.
- IA : OpenAI appele uniquement depuis le backend.
- Mobile : Flutter Android avec `BACKEND_BASE_URL` injecte au build.

## Prerequis

1. Un compte Google Cloud avec facturation active (si Cloud Run).
2. Google Cloud CLI installe : `gcloud`.
3. Un projet Google Cloud, par exemple `pulsenote-prod`.
4. Une cle OpenAI valide.
5. `backend\.env` rempli localement pour que les scripts puissent lire :
   - `OPENAI_API_KEY`
   - `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`

## Deployer le backend

Depuis la racine du projet :

```powershell
.\scripts\deploy_cloud_run.ps1 -ProjectId "TON_PROJECT_ID"
```

Le script :

- active les APIs Google necessaires ;
- cree les secrets `pulsenote-openai-api-key` et
  `pulsenote-supabase-service-role-key` ;
- deploie le backend sur Cloud Run ;
- affiche l'URL HTTPS de production.

## Verifier le backend production

```powershell
.\scripts\check_production_backend.ps1 -BackendBaseUrl "https://TON-SERVICE.a.run.app"
```

Le test doit afficher `ok: true` pour `/health` et confirmer que `/summarize`
refuse un appel non authentifie.

## Builder le bundle production

```powershell
.\scripts\build_release_apk.ps1 -BackendBaseUrl "https://TON-SERVICE.a.run.app"
```

Le bundle sera genere ici :

```text
build\app\outputs\bundle\release\app-release.aab
```

## Authentification

L'authentification utilisateur (email/mot de passe + Google) est geree par
Supabase Auth. Le backend valide le token envoye par l'app via
`supabase.auth.getUser(token)` (voir `requireAuth` dans `src/server.js`) ;
il lui faut donc `SUPABASE_URL` et `SUPABASE_ANON_KEY` en variables
d'environnement (memes secrets que cote Flutter).

## Important avant publication

Les routes IA exigent un utilisateur Supabase connecte et verifient le palier
Pro ainsi que les credits cote backend. Pour activer la verification Google
Play et la suppression de compte sur Render, ajouter ces secrets :

- `SUPABASE_SERVICE_ROLE_KEY` : cle `service_role` du projet Supabase ;
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` : contenu JSON complet du compte de
  service autorise dans Play Console.
- `GOOGLE_PUBSUB_PUSH_AUDIENCE` :
  `https://pulsenote.onrender.com/billing/google-play/rtdn` ;
- `GOOGLE_PUBSUB_PUSH_SERVICE_ACCOUNT_EMAIL` : compte de service utilise par
  la souscription Push Pub/Sub pour signer ses appels OIDC.

Executer aussi `supabase/schema.sql` dans le SQL Editor Supabase afin de creer
`user_entitlements` et les fonctions atomiques de debit/remboursement des
credits. Ne jamais integrer ces deux secrets dans l'application mobile.

Le backend reverifie egalement un abonnement actif au maximum toutes les
15 minutes lorsqu'un utilisateur ouvre l'application. Les notifications RTDN
permettent en plus de traiter sans attente les renouvellements, retraits et
remboursements. Voir `docs/google_play_rtdn.md`.
