# ranking-beach-tennis-app

Flutter app (Android, iOS and web) of the beach tennis individual ranking. The backend lives in its
own repository (`ranking-beach-tennis`). The user interface is in Brazilian Portuguese.

## Structure

Feature-first, with Riverpod for state, go_router for navigation and Dio for HTTP:

| Path | Content |
|---|---|
| `lib/core/` | Configuration, theme (light/dark/system), HTTP client and errors, routing |
| `lib/features/auth/` | Sign-in (Google, e-mail/password). Firebase stays behind `AuthRepository`. |
| `lib/features/me/` | The signed-in player's profile (`/api/me`, admin flag) |
| `lib/features/ranking/` | Current ranking, past seasons |
| `lib/features/matches/` | Match registration, history with filters, match details and audit |
| `lib/features/players/` | Players list and profiles |
| `lib/features/sync/` | Offline outbox of registered matches and automatic sync |
| `lib/features/home/` | Bottom navigation with the five areas (the same for every player) |
| `lib/features/notifications/` | In-app notifications, unread badge, push token registration (FCM behind `PushMessaging`) |
| `lib/features/profile/` | Profile tab: display name, theme, sign-out and, for the administrator, the administration section (seasons) |

## Firebase setup

Android, iOS and web are configured for the Firebase project `ranking-beach-tennis`: `lib/firebase_options.dart`,
`android/app/google-services.json` (with the OAuth clients) and `firebase.json` are committed.
Google and e-mail/password sign-in are enabled and the SHA-1 of the debug key is registered.
iOS reads its Firebase settings from `firebase_options.dart`; `ios/Runner/GoogleService-Info.plist`
is kept for reference and is not part of the Xcode project. Google Sign-In on iOS uses `GIDClientID`
and the reversed client ID URL scheme in `ios/Runner/Info.plist`. The iOS deployment target is 15.0
(required by the Firebase plugins).

To regenerate the files (e.g. after adding a SHA-1 or registering iOS), with the
[Firebase CLI](https://firebase.google.com/docs/cli) logged in and `flutterfire_cli` activated
(`dart pub global activate flutterfire_cli`; the `run` form below avoids changing PATH):

```bash
dart pub global run flutterfire_cli:flutterfire configure --project=ranking-beach-tennis --platforms=android,ios,web --android-package-name=com.lucchetta.rankingBeachTennis --ios-bundle-id=com.lucchetta.rankingBeachTennis --yes --overwrite-firebase-options
```

Building on another machine requires adding that machine's debug SHA-1
(`cd android && ./gradlew signingReport`) in Project settings → Android app, otherwise Google
Sign-In fails.

## Run

Start the backend locally. On a phone connected by USB (USB debugging on), forward the
backend port through the cable and point the app to `localhost`:

```bash
adb reverse tcp:8080 tcp:8080
flutter run --dart-define=API_BASE_URL=http://localhost:8080 --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>
```

`adb reverse` is lost when the cable is unplugged; run it again. On the Android emulator the
default `API_BASE_URL` already reaches the development machine.

| Define | Description | Default |
|---|---|---|
| `API_BASE_URL` | Backend URL | `http://10.0.2.2:8080` (backend on the dev machine, seen from the Android emulator) |
| `FIREBASE_AUTH_DOMAIN` | Web only: Firebase Auth domain (e.g. the Hosting domain) | `ranking-beach-tennis.firebaseapp.com` |
| `GOOGLE_SERVER_CLIENT_ID` | Web OAuth client ID of the Firebase project (Authentication → Google → Web SDK configuration) | empty |

Plain HTTP is allowed only in debug builds (`android/app/src/debug/AndroidManifest.xml`).

## iPhone without a Mac (free Apple ID)

The workflow `.github/workflows/ios-unsigned.yml` (run it manually in GitHub Actions) builds an
unsigned `ranking-beach-tennis.ipa` on a macOS runner and keeps it as a 7-day artifact. Install it
on your own iPhone from Windows with [Sideloadly](https://sideloadly.io/), signing with a free Apple
ID (keep the original bundle ID, or Google Sign-In fails). Limits of a free Apple ID: the app expires
after 7 days, at most 3 such apps per device, and no push notifications (in-app notifications still
work). The backend must be reachable from the iPhone over HTTPS; for a local test only, tick
`allow_http` and use `http://<PC IP on the Wi-Fi>:8080` (the Windows firewall must allow inbound TCP
8080 on the private network, and the iPhone asks for local network access).

## Web (PWA)

The same app runs in the browser and can be added to the home screen (Safari on iPhone included),
with no store or signing. Differences on the web: local data lives in the browser storage
(`PreferencesLocalStore`), Google sign-in uses a Firebase Auth popup, and there is no push (in-app
notifications still work). The backend must allow the site origin (CORS) and be served over HTTPS.

```bash
flutter run -d chrome --web-port 5000 --dart-define=API_BASE_URL=http://localhost:8080
flutter build web --release --dart-define=API_BASE_URL=https://<backend> --dart-define=FIREBASE_AUTH_DOMAIN=ranking-beach-tennis.web.app
```

`FIREBASE_AUTH_DOMAIN` (web only, optional) serves the sign-in pages from the site domain when it is
hosted on Firebase Hosting.

## Production

API: `https://api.ranking-beach-tennis.tech` (CORS allows the two Firebase Hosting domains).

**Web** (Firebase Hosting, configured in `firebase.json`):

```bash
flutter build web --release --dart-define=API_BASE_URL=https://api.ranking-beach-tennis.tech
firebase deploy --only hosting --project ranking-beach-tennis
```

**Android** (Firebase App Distribution). Release builds are signed with the key referenced by
`android/key.properties` (git-ignored; the keystore lives outside the repository). Its SHA-1 must be
registered in the Firebase Android app, or Google Sign-In fails. Raise `version` in `pubspec.yaml`
for every release. Each release build also leaves a copy named after the version, ready to share:
`build/app/outputs/shareable/ranking-beach-tennis-<version>.apk`. If `android/release.properties`
(git-ignored) sets `releaseCopyDir`, the APK is also copied to that folder and the APKs of older
versions there are deleted.

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.ranking-beach-tennis.tech --dart-define=GOOGLE_SERVER_CLIENT_ID=780647009353-jkckmv4ct9lu93o7utqbalafcanqeboi.apps.googleusercontent.com
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk --app 1:780647009353:android:dd9cd215836edc11f44398 --testers "<emails>" --release-notes "<notes>"
```

## App icon

The logo lives in `assets/branding/`: SVG sources (`app_icon.svg` for the full icon,
`app_icon_foreground.svg` and `app_icon_background.svg` for the Android adaptive icon) and the
1024×1024 PNGs rendered from them. The login screen shows `app_icon.png`. After changing the
PNGs, regenerate the Android and iOS launcher icons:

```bash
dart run flutter_launcher_icons
```

The tool also rewrites `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` in
`ios/Runner.xcodeproj/project.pbxproj` to an invalid value; discard that change
(`git checkout -- ios/Runner.xcodeproj/project.pbxproj`).

## Contributing

Branches, pull requests and releases: see [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Tests

```bash
flutter analyze
flutter test
```
