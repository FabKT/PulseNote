# Google Play Billing - Ultimate Audio Recorder

## Produits à créer

Deux abonnements distincts (le palier Pro est cumulatif côté application :
un utilisateur Pro a accès à toutes les fonctionnalités du palier Plus,
sans avoir besoin d'acheter les deux) :

| ID produit | Nom public suggéré | Rythme | Prix |
|---|---|---|---|
| `ultimate_audio_recorder_plus_monthly` | Ultimate Audio Recorder Plus | mensuel | 3,99 € |
| `ultimate_audio_recorder_pro_monthly` | Ultimate Audio Recorder Pro | mensuel | 8,99 € |

Les ID doivent être strictement identiques à ceux définis dans
`lib/config/billing_config.dart` (`plusSubscriptionId`, `proSubscriptionId`).

## Contenu par palier (pour la fiche produit / description)

- **Gratuit** : enregistrements normaux, créneaux programmés (horaire),
  dossiers, 500 Mo de sauvegarde cloud.
- **Plus** (3,99€) : + lecture continue, import audio, MP4 vers MP3,
  créneaux programmés (mots-clés), lecture planifiée.
- **Pro** (8,99€) : tout Plus, + transcription audio et résumé IA.

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
