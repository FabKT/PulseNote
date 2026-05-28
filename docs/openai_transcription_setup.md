# Transcription réelle - architecture recommandée

## Choix technique

Pour Ultimate Audio Recorder, l'option recommandée est OpenAI :

- Fichiers audio enregistrés : `gpt-4o-transcribe`
- Transcription instantanée : Realtime transcription avec session éphémère
- Langue par défaut : `fr`

La clé OpenAI ne doit pas être intégrée dans l'APK. Elle doit rester sur un backend.

## Architecture

```text
Flutter app
  -> envoie un fichier audio ou demande une session temps réel
Backend sécurisé
  -> utilise OPENAI_API_KEY
OpenAI API
  -> renvoie transcription
Backend
  -> renvoie texte ou token éphémère à l'app
```

## Ce que tu dois créer

### 1. Compte OpenAI

1. Va sur https://platform.openai.com
2. Crée/connecte ton compte.
3. Ajoute un moyen de paiement.
4. Crée une clé API.
5. Ne colle jamais cette clé dans Flutter.

### 2. Backend minimal

Créer un petit backend Node.js, par exemple sur Render, Railway, Fly.io, Supabase Edge Functions ou Firebase Functions.

Variables d'environnement :

```env
OPENAI_API_KEY=ta_cle_openai
```

Endpoints à exposer :

```text
POST /transcribe
POST /realtime/transcription-session
POST /summarize
```

### 3. Endpoint fichier enregistré

`POST /transcribe`

- Entrée : multipart/form-data avec un fichier `audio`
- Sortie :

```json
{
  "text": "Transcription complète..."
}
```

Le backend appelle OpenAI avec le modèle `gpt-4o-transcribe`.

### 4. Endpoint transcription instantanée

`POST /realtime/transcription-session`

- Entrée : utilisateur authentifié / app autorisée
- Sortie : token éphémère OpenAI

L'app Flutter utilise ensuite ce token pour ouvrir une connexion Realtime transcription.

### 5. Endpoint résumé

`POST /summarize`

- Entrée :

```json
{
  "text": "Transcription..."
}
```

- Sortie :

```json
{
  "summary": "Résumé structuré..."
}
```

## Étapes côté Flutter

1. Remplacer `TranscriptionService.transcribeAudio()` par un upload vers `/transcribe`.
2. Remplacer `TranscriptionService.transcribeLiveSegment()` par une connexion Realtime.
3. Remplacer `SummaryService.summarizeText()` par un appel vers `/summarize`.
4. Ajouter une configuration d'URL backend, par exemple :

```dart
const backendBaseUrl = 'https://ton-backend.com';
```

5. Ajouter gestion réseau :
   - absence internet,
   - timeout,
   - fichier trop volumineux,
   - quota dépassé,
   - abonnement non actif.

## À me fournir pour brancher le code Flutter

Quand ton backend existe, fournis-moi :

- URL de base du backend.
- Format exact de réponse de `/transcribe`.
- Format exact de réponse de `/summarize`.
- Endpoint de session Realtime.
- Système d'authentification choisi, si présent.

Je pourrai ensuite remplacer les services simulés par les appels réels.
