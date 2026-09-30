# Google Play Billing - Ultimate Audio Recorder

## Produits à créer

Deux abonnements distincts (le palier Pro est cumulatif côté application :
un utilisateur Pro a accès à toutes les fonctionnalités du palier Plus,
sans avoir besoin d'acheter les deux) :

| ID produit | Nom public suggéré | Rythme | Prix |
|---|---|---|---|
| `ultimate_audio_recorder_plus_monthly` | Ultimate Audio Recorder Plus | mensuel | 2,99 € |
| `ultimate_audio_recorder_pro_monthly` | Ultimate Audio Recorder Pro | mensuel | 9,99 € |

Les ID doivent être strictement identiques à ceux définis dans
`lib/config/billing_config.dart` (`plusSubscriptionId`, `proSubscriptionId`).

## Création automatisée via l'API (recommandé)

Plutôt que de créer les deux abonnements à la main, `backend/scripts/create-play-subscriptions.js`
les crée (ou les met à jour) via l'API Google Play Developer.

Prérequis, à faire une seule fois dans Play Console :

1. La fiche app `com.fabkt.ultimateaudiorecorder` doit déjà exister (créée
   manuellement, même sans build téléversé).
2. Paramètres > Accès API > créer/lier un compte de service Google Cloud,
   puis lui donner le droit **"Gérer les commandes et abonnements"**.
3. Télécharger la clé JSON de ce compte de service et la placer à
   `backend/google-play-service-account.json` (jamais commité — voir
   `.gitignore`), ou pointer `GOOGLE_PLAY_SERVICE_ACCOUNT_PATH` (dans
   `backend/.env`) vers un autre emplacement.

Puis, depuis `backend/` :

```bash
npm run play:create-subscriptions
```

Le script crée chaque abonnement en état `DRAFT` avec un prix en euros sur
les principaux marchés européens (+ une conversion automatique pour le
reste du monde via `otherRegionsConfig`), puis active le base plan. Si un
produit existe déjà, il est mis à jour plutôt que recréé. Vérifier ensuite
dans Play Console > Monétisation > Produits que tout est correct (prix,
libellés) avant de t'appuyer dessus en production.

## Contenu par palier (pour la fiche produit / description)

- **Gratuit** : enregistrements normaux, créneaux programmés (horaire),
  dossiers, import audio, MP4 vers MP3, 500 Mo de sauvegarde cloud.
- **Plus** (2,99€) : + lecture continue,
  créneaux programmés (mots-clés), lecture planifiée.
- **Pro** (9,99€) : tout Plus, + transcription audio, résumé IA et
  1 000 crédits IA renouvelés chaque mois sans report.

## Parcours de test

1. Créer l'application dans Google Play Console.
2. Configurer la signature et téléverser un build Android.
3. Créer les deux abonnements ci-dessus.
4. Ajouter des testeurs de licence dans Play Console.
5. Publier sur une piste de test interne.
6. Installer l'app depuis le lien Play Store de test.
7. Ouvrir le paywall dans l'app (bouton "Abonnez-vous Pro" du menu, ou tout
   déclencheur de fonctionnalité verrouillée) et vérifier, pour chaque
   palier :
   - affichage du prix,
   - achat,
   - restauration,
   - déverrouillage effectif des fonctionnalités du palier.

## Notes importantes

- Un APK installé manuellement peut ne pas recevoir les produits Google Play.
- Les boutons `Test : Gratuit/Plus/Pro` (bascule manuelle de palier) sont
  visibles uniquement en build debug (`kDebugMode`).
- Avant publication, il faudra ajouter une vérification serveur des reçus
  pour éviter qu'un achat simulé localement soit traité comme définitif.
