# Google Play Billing - Ultimate Audio Recorder Premium

## Produit à créer

- Type : abonnement
- ID produit : `ultimate_audio_recorder_premium_monthly`
- Nom public suggéré : `Ultimate Audio Recorder Premium`
- Rythme : mensuel

L'ID doit être strictement identique à celui défini dans `lib/config/billing_config.dart`.

## Parcours de test

1. Créer l'application dans Google Play Console.
2. Configurer la signature et téléverser un build Android.
3. Créer l'abonnement `ultimate_audio_recorder_premium_monthly`.
4. Ajouter des testeurs de licence dans Play Console.
5. Publier sur une piste de test interne.
6. Installer l'app depuis le lien Play Store de test.
7. Ouvrir un paywall dans l'app et vérifier :
   - affichage du prix,
   - achat,
   - restauration,
   - déverrouillage Premium.

## Notes importantes

- Un APK installé manuellement peut ne pas recevoir les produits Google Play.
- Le bouton `Mode test : activer Premium` est visible uniquement en build debug.
- Avant publication, il faudra ajouter une vérification serveur des reçus pour éviter qu'un achat simulé localement soit traité comme définitif.
