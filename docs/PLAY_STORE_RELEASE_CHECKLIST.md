# Publication Google Play - Ultimate Audio Recorder

## Fiche Store en français

**Nom (30 caractères maximum)**

Ultimate Audio Recorder

**Description courte**

Enregistrez, planifiez, organisez et transcrivez vos audios simplement.

**Description complète**

Ultimate Audio Recorder réunit l'enregistrement, l'organisation et le
traitement audio dans une interface claire.

- Enregistrement manuel et enregistrement horaire planifié
- Classement dans des dossiers et favoris
- Import de fichiers audio et conversion MP4 vers MP3
- Lecture continue et lecture planifiée avec le palier Plus
- Déclenchement par mots-clés avec le palier Plus
- Transcription et résumé assistés par IA avec le palier Pro
- Sauvegarde cloud et synchronisation entre appareils

Le palier Pro comprend 1 000 crédits IA renouvelés chaque mois, sans report.
Une minute de transcription entamée utilise un crédit. Le résumé de la
transcription ne consomme pas de crédit supplémentaire.

L'enregistrement d'une conversation peut être soumis au consentement des
participants selon votre pays. Vous êtes responsable du respect de la loi
applicable.

## Formulaires Play Console

- Catégorie suggérée : Productivité
- Application : gratuite avec achats intégrés
- Contient des annonces : **non** (aucun SDK publicitaire intégré)
- Public cible : 18 ans et plus
- Accès à l'application : fournir un compte de démonstration fonctionnel
- Politique : `https://zippy-pithivier-16e4a6.netlify.app/`
- Suppression :
  `https://zippy-pithivier-16e4a6.netlify.app/suppression-compte.html`

## Sécurité des données

Déclarer au minimum, selon les fonctionnalités effectivement activées :

- adresse email et identifiant utilisateur : gestion du compte ;
- fichiers audio : fonctionnalité de l'application, sauvegarde cloud et IA ;
- transcriptions, résumés et dossiers : fonctionnalité et synchronisation ;
- informations d'achat et statut d'abonnement : gestion des abonnements ;
- activité dans l'application : demandes d'amis, messages et dossiers partagés ;
- contenu utilisateur : messages texte, messages audio et fichiers partagés.

Les données sont chiffrées en transit. L'utilisateur peut demander leur
suppression dans l'application et sur le site public.

## Service de premier plan et microphone

Le manifeste ne demande plus `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. Ne pas
déclarer cette permission dans Play Console. L'utilisateur peut toujours ouvrir
manuellement les réglages Android depuis l'application si son constructeur
interrompt abusivement les tâches en arrière-plan.

Le manifeste conserve `FOREGROUND_SERVICE` et
`FOREGROUND_SERVICE_MICROPHONE`, avec le type de service `microphone`. Dans
Play Console, ouvrir **Règles et programmes > Contenu de l'application >
Autorisations des services de premier plan** et déclarer :

- type : **Microphone** ;
- cas d'utilisation : **Accès audio en arrière-plan / Enregistrement vocal** ;
- fonctionnalité : « L'utilisateur démarre explicitement une session ou un
  enregistrement. Le service maintient la capture audio lorsque l'écran est
  éteint ou que l'utilisateur ouvre une autre application. Une notification
  permanente indique que l'écoute ou l'enregistrement est actif et permet à
  l'utilisateur de revenir dans l'application pour l'arrêter. » ;
- impact d'une interruption : « Une interruption coupe l'enregistrement,
  produit un fichier incomplet et empêche un créneau déjà activé de fonctionner
  comme demandé par l'utilisateur. »

La vidéo de déclaration doit montrer, sur un appareil Android :

1. l'ouverture de l'application et l'autorisation du microphone ;
2. le démarrage manuel d'une session puis d'un enregistrement ;
3. la notification permanente visible ;
4. le retour à l'écran d'accueil du téléphone pendant que l'enregistrement
   continue ;
5. le retour dans l'application et l'arrêt explicite de l'enregistrement.

Utiliser une vidéo courte, sans montage trompeur, accessible à l'équipe de
validation via YouTube non répertorié ou Google Drive.

## Test fermé obligatoire pour un compte personnel récent

Si le compte développeur personnel a été créé après le 13 novembre 2023 :

1. Terminer la configuration de l'application dans Play Console.
2. Créer une piste de test fermé et y publier l'AAB.
3. Créer une liste de testeurs et obtenir au moins 12 inscriptions effectives.
4. Chaque testeur ouvre le lien d'adhésion avec son compte Google et choisit
   de participer au test.
5. Conserver au moins 12 testeurs inscrits sans interruption pendant 14 jours
   consécutifs. Un testeur qui quitte puis revient recommence son délai.
6. Faire réellement tester les parcours principaux et conserver les retours.
7. Après les 14 jours, demander l'accès à la production depuis le tableau de
   bord et répondre aux questions de Google sur les tests et corrections.

Une piste de test interne ne remplace pas ce test fermé. Les testeurs peuvent
être des proches, collègues ou utilisateurs volontaires. Ils doivent rester
inscrits avec le même compte Google pendant toute la période.

## Ordre de mise en production

1. Déployer le dossier Netlify et vérifier les trois URL légales.
2. Exécuter `supabase/schema.sql` dans Supabase SQL Editor.
3. Ajouter `SUPABASE_SERVICE_ROLE_KEY` sur Render.
4. Créer le compte de service Play, puis ajouter son JSON dans le secret Render
   `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.
5. Redéployer le backend et tester `/health`, `/me/entitlements`, la suppression
   de compte et une transcription avec crédits.
6. Créer et activer les abonnements 2,99 € et 9,99 € dans Play Console.
7. Déclarer « Ne contient pas d'annonces » dans Play Console.
8. Incrémenter la version, reconstruire et téléverser l'AAB.
9. Compléter les formulaires, déclarations microphone/service de premier plan,
   captures d'écran et accès de démonstration.
10. Lancer le test fermé de 14 jours, puis demander l'accès production.
