# Déploiement Netlify

Ce dossier est un site statique autonome. Il ne nécessite ni commande de
construction, ni dépendance, ni variable d'environnement, ni token d'accès.

## Mettre à jour le site existant

1. Connectez-vous au compte Netlify qui possède le site
   `zippy-pithivier-16e4a6`.
2. Ouvrez le projet, puis **Deploys**.
3. Glissez le dossier `privacy_policy_site` complet dans la zone de déploiement
   manuel. Vous pouvez aussi y déposer l'archive
   `Ultimate_Audio_Recorder_Netlify.zip` sans la décompresser.
4. Attendez l'état **Published**.
5. Vérifiez les URL ci-dessous dans une fenêtre privée.

Ne créez pas un nouveau projet Netlify : cela changerait l'URL déjà déclarée
dans l'application et dans Google Play Console.

## URL à vérifier

- Politique : `https://zippy-pithivier-16e4a6.netlify.app/`
- Conditions : `https://zippy-pithivier-16e4a6.netlify.app/conditions.html`
- Suppression : `https://zippy-pithivier-16e4a6.netlify.app/suppression-compte.html`
- Alias de suppression : `https://zippy-pithivier-16e4a6.netlify.app/delete-account`

## Contenu du dossier

- `index.html` : politique de confidentialité.
- `conditions.html` : conditions d'utilisation.
- `suppression-compte.html` : instructions publiques de suppression de compte.
- `404.html` : page d'erreur.
- `_headers` et `netlify.toml` : en-têtes de sécurité et de cache.
- `_redirects` et `netlify.toml` : alias d'URL stables.

Le CSS est inclus dans chaque page HTML. Le déploiement ne dépend donc d'aucun
fichier CSS externe.

## Réglages Netlify

Si Netlify demande des réglages lors d'un déploiement manuel :

- Build command : laisser vide.
- Publish directory : `/` ou laisser vide.
- Functions directory : laisser vide.

## Contrôles Google Play

- Nom de l'application : **Ultimate Audio Recorder**.
- Contact : `tayoufabiokamogne@gmail.com`.
- La fiche Play Console doit indiquer **Ne contient pas d'annonces**.
- L'URL de suppression de compte doit pointer vers la page publique ci-dessus.
