# giggre_app

The Giggre mobile app (Flutter + Firebase).

## Environments

The app uses build flavors to select the Firebase project automatically — no manual config swapping.

| Flavor | Firebase project      | Used for                     |
| ------ | --------------------- | ---------------------------- |
| dev    | `simpleproject-8ff7a` | Day-to-day development       |
| prod   | `giggre-prod`         | Play Store production builds |

The flavor is read at startup in `lib/main.dart`, which loads either `firebase_options_dev.dart` or `firebase_options_prod.dart`.

> Always keep `--flavor` and `--dart-define=FLAVOR=` matching. Don't mix `--flavor prod` with `FLAVOR=dev`.

## Running (development)

```bash
flutter run --flavor dev --dart-define=FLAVOR=dev
```

## Building for production

Build the AAB for Play Store, pointing at `giggre-prod`:

```bash
flutter build appbundle --flavor prod --dart-define=FLAVOR=prod
```

### Other builds

```bash
# Dev APK (shareable test build)
flutter build apk --flavor dev --dart-define=FLAVOR=dev

# Prod APK (installable prod build, not for Play upload)
flutter build apk --flavor prod --dart-define=FLAVOR=prod
```

### Optional shortcut aliases (Git Bash)

Add to `~/.bashrc`, then `source ~/.bashrc`:

```bash
alias gdev='flutter run --flavor dev --dart-define=FLAVOR=dev'
alias gprod='flutter run --flavor prod --dart-define=FLAVOR=prod'
alias gbuild='flutter build appbundle --flavor prod --dart-define=FLAVOR=prod'
```

## Before a production upload — checklist

- [ ] `versionCode` bumped (Play rejects duplicate version codes)
- [ ] `firebase_options_prod.dart` resolves `projectId` to `giggre-prod`
- [ ] Cloud Functions deployed to `giggre-prod` (`asia-east2`)
- [ ] Firestore rules deployed to prod
- [ ] Upload SHA1 registered on the prod Android app (for Google sign-in)
- [ ] OAuth consent screen published (not in Testing mode)

## Flutter resources

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Flutter documentation](https://docs.flutter.dev/)