# Déploiement de la politique de confidentialité

Site statique complet requis par Google Play Console.

**URL actuellement en ligne :** https://zippy-pithivier-16e4a6.netlify.app/

## Déploiement par glisser-déposer

1. Ouvrir https://app.netlify.com/drop
2. Glisser le dossier `privacy_policy_site` dans la zone de dépôt.
3. Attendre la fin du déploiement.
4. Vérifier les trois URL indiquées ci-dessous.
5. Conserver le même site Netlify afin que les URL déclarées dans l'app et
   Play Console ne changent pas.

## URL à vérifier

- Politique : `https://zippy-pithivier-16e4a6.netlify.app/`
- Conditions : `https://zippy-pithivier-16e4a6.netlify.app/conditions.html`
- Suppression : `https://zippy-pithivier-16e4a6.netlify.app/suppression-compte.html`

## Fichiers

- `index.html` : politique de confidentialité.
- `conditions.html` : conditions d'utilisation et formules commerciales.
- `suppression-compte.html` : procédure publique de suppression de compte.
- Le CSS est intégré dans chaque page
  (balise `<style>`), il n'y a volontairement plus de `styles.css` séparé.
  Un premier déploiement n'avait envoyé que `index.html`, laissant le site
  sans aucun style (`styles.css` renvoyait 404) : tout intégrer rend la page
  impossible à casser, même si un seul fichier est transféré.
- `netlify.toml` : en-têtes de sécurité et redirections courtes.

## À vérifier avant chaque publication Play Store

- Le nom de l'application sur la page doit correspondre exactement à celui de
  la fiche Play Store (**Ultimate Audio Recorder**) : Google contrôle cette
  cohérence.
- Les prestataires cités (Supabase, OpenAI, Google Play Billing) doivent
  correspondre à ceux réellement utilisés par l'application et au formulaire
  « Sécurité des données » de Play Console.
- La date de dernière mise à jour en haut de page doit être actualisée.

## Contact

La page indique l'adresse de contact suivante:

```text
tayoufabiokamogne@gmail.com
```
