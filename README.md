# Xynpo Mobile

Application Flutter connectée à l’API Symfony du dossier `Web` (auth JWT mobile).

## APK

<p align="center">
	<a href="./android/app/build/outputs/flutter-apk/app-release.apk"><strong>Télécharger l’APK</strong></a>
</p>

Ce lien pointe vers l’emplacement généré après un `flutter build apk --release`.

## Prérequis

- Flutter SDK installé
- Un device Android/iOS (émulateur ou téléphone)
- API Symfony démarrée côté `Web`

## Endpoints utilisés

- `POST /api/mobile/login`
- `GET /api/mobile/patients`
- `GET /api/mobile/patients/{id}`
- `GET /api/mobile/rdv`
- `GET /api/mobile/patients/{id}/photos`
- `POST /api/mobile/patients/{id}/photos`

## Lancer l’app mobile

Depuis ce dossier (`mobile`) :

```bash
flutter clean
flutter pub get
flutter run --dart-define=API_BASE_URL=http://IP_OU_DOMAINE
```

Exemple LAN :

```bash
flutter run --dart-define=API_BASE_URL=http://10.31.252.81
```

Exemple ngrok :

```bash
flutter run --dart-define=API_BASE_URL=https://xxxx.ngrok-free.dev
```

## Configuration URL API

- L’URL est configurable au runtime via `--dart-define=API_BASE_URL=...`.
- Valeur par défaut définie dans `lib/main.dart` (`ApiConfig.baseUrl`).
- Ne pas ajouter `/api/mobile` dans `API_BASE_URL` (le code l’ajoute déjà).

## Utilisation avec ngrok

Si tu exposes l’API via ngrok, lance de préférence :

```bash
ngrok http 80 --host-header=localhost
```

Puis utilise l’URL `https://...ngrok...` comme `API_BASE_URL`.

## Dépannage rapide

### Erreur "No pubspec.yaml file found"

Tu n’es pas dans le bon dossier.

```bash
cd c:\Users\npichon\Desktop\feut\mobile
```

### Erreur "Réponse login invalide (308...)" ou "Trop de redirections login"

- Souvent lié au tunnel/proxy (ngrok) ou au host de destination.
- Vérifie `ngrok http 80 --host-header=localhost`.
- Vérifie que l’URL fournie à `API_BASE_URL` est bien l’URL publique active.
- Redémarre complètement l’app (pas seulement hot reload).

### Erreur "Token manquant dans la réponse API"

- La réponse n’est pas celle attendue (HTML/warning/proxy/redirection) ou credentials invalides.
- Vérifie que `/api/mobile/login` répond bien en JSON.
- Vérifie email/mot de passe et que le compte existe en base.

### "Lost connection to device"

Souvent ADB/USB et pas l’API :

```bash
adb kill-server
adb start-server
adb devices
```

Puis relance `flutter run`.
