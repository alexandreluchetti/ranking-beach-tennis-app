/// Build-time configuration, set with `--dart-define`.
class AppConfig {
  const AppConfig._();

  /// Backend base URL. The default reaches a backend running on the development
  /// machine from the Android emulator.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// OAuth client ID of type "Web" from the Firebase project, needed by Google
  /// Sign-In on Android to obtain an ID token for Firebase.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
}
