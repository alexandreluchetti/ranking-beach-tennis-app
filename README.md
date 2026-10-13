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
| `lib/features/home/` | Bottom navigation with the five areas |
| `lib/features/settings/` | Theme choice and sign-out |

## One-time Firebase setup

The app needs the Firebase project `ranking-beach-tennis` configured for Android and iOS. With
the [Firebase CLI](https://firebase.google.com/docs/cli) and FlutterFire CLI installed and
logged in:

```bash
flutterfire configure --project=ranking-beach-tennis --platforms=android,ios
```

This replaces `lib/firebase_options.dart` and adds `android/app/google-services.json` and
`ios/Runner/GoogleService-Info.plist`. Then, in the Firebase console:

1. Authentication → Sign-in method: enable **Google** and **E-mail/senha**.
2. Project settings → your Android app: add the **SHA-1** of the debug key
   (`cd android && ./gradlew signingReport`), required by Google Sign-In.
3. Copy the **Web client ID** (Authentication → Google → Web SDK configuration) and pass it as
   `GOOGLE_SERVER_CLIENT_ID` (below).

## Run

Start the backend locally, then (Android emulator):

```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>
```

| Define | Description | Default |
|---|---|---|
| `API_BASE_URL` | Backend URL | `http://10.0.2.2:8080` (backend on the dev machine, seen from the Android emulator) |
| `GOOGLE_SERVER_CLIENT_ID` | Web OAuth client ID of the Firebase project | empty |

Plain HTTP is allowed only in debug builds (`android/app/src/debug/AndroidManifest.xml`).

## Tests

```bash
flutter analyze
flutter test
```
