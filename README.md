# ranking-beach-tennis-app

Flutter app (Android and iOS) of the beach tennis individual ranking. The backend lives in its
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
| `lib/features/home/` | Bottom navigation with the five areas |
| `lib/features/notifications/` | In-app notifications, unread badge, push token registration (FCM behind `PushMessaging`) |
| `lib/features/settings/` | Display name, theme choice and sign-out |

## Firebase setup

Android is configured for the Firebase project `ranking-beach-tennis`: `lib/firebase_options.dart`,
`android/app/google-services.json` (with the OAuth clients) and `firebase.json` are committed.
Google and e-mail/password sign-in are enabled and the SHA-1 of the debug key is registered.
**iOS is not registered in Firebase yet**; `DefaultFirebaseOptions` throws on iOS until it is.

To regenerate the files (e.g. after adding a SHA-1 or registering iOS), with the
[Firebase CLI](https://firebase.google.com/docs/cli) logged in and `flutterfire_cli` activated
(`dart pub global activate flutterfire_cli`; the `run` form below avoids changing PATH):

```bash
dart pub global run flutterfire_cli:flutterfire configure --project=ranking-beach-tennis --platforms=android --android-package-name=com.lucchetta.rankingBeachTennis --yes --overwrite-firebase-options
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
| `GOOGLE_SERVER_CLIENT_ID` | Web OAuth client ID of the Firebase project (Authentication → Google → Web SDK configuration) | empty |

Plain HTTP is allowed only in debug builds (`android/app/src/debug/AndroidManifest.xml`).

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

## Tests

```bash
flutter analyze
flutter test
```
