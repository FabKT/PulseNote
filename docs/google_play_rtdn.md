# Notifications Google Play en temps réel (RTDN)

Le backend expose :

```text
POST https://pulsenote.onrender.com/billing/google-play/rtdn
```

Cette route vérifie le jeton OIDC signé par Google avant de traiter une
notification. Elle ne doit pas être configurée comme un webhook anonyme.

## Configuration Google Cloud

1. Dans le projet Google Cloud lié à Play Console, activez **Pub/Sub API** et
   **Google Play Android Developer API**.
2. Créez un topic Pub/Sub, par exemple `ultimate-audio-recorder-rtdn`.
3. Dans Play Console, ouvrez **Monétisation > Configuration de la
   monétisation**, indiquez le topic complet
   `projects/PROJECT_ID/topics/ultimate-audio-recorder-rtdn`, puis envoyez une
   notification de test.
4. Créez un compte de service dédié, par exemple
   `play-rtdn-push@PROJECT_ID.iam.gserviceaccount.com`. Il sert uniquement à
   signer les appels Push ; ne téléchargez pas de clé JSON pour ce compte.
5. Autorisez l'agent de service Pub/Sub à créer des jetons pour ce compte de
   service, conformément à la documentation Google Pub/Sub.
6. Créez une souscription **Push** sur le topic avec l'URL ci-dessus.
7. Activez l'authentification de la souscription Push avec le compte de service
   dédié et utilisez comme audience exacte :

```text
https://pulsenote.onrender.com/billing/google-play/rtdn
```

## Variables Render

Ajoutez :

```text
GOOGLE_PUBSUB_PUSH_AUDIENCE=https://pulsenote.onrender.com/billing/google-play/rtdn
GOOGLE_PUBSUB_PUSH_SERVICE_ACCOUNT_EMAIL=play-rtdn-push@PROJECT_ID.iam.gserviceaccount.com
```

`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` reste nécessaire : il permet au backend de
relire l'état officiel de l'abonnement après réception de la notification.

Redéployez ensuite Render et renvoyez une notification de test depuis Play
Console. Une requête authentifiée et comprise répond `204`. Les erreurs
temporaires répondent `500`, afin que Pub/Sub les retente.

## Fonctionnement de secours

Même si RTDN est momentanément indisponible, `/me/entitlements` revalide auprès
de Google Play tout abonnement dont la dernière vérification remonte à plus de
15 minutes. Un remboursement est donc retiré rapidement dès que l'utilisateur
rouvre l'application, et plus uniquement à la fin de la période payée.
