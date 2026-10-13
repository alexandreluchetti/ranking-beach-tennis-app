import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/storage/local_store.dart';
import 'core/storage/open_local_store.dart';
import 'core/storage/preferences.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: _firebaseOptions());
  await initializeDateFormatting('pt_BR');
  final preferences = await SharedPreferences.getInstance();
  final localStore = await openLocalStore(preferences);
  runApp(
    ProviderScope(
      // Failures are shown with a "Tentar novamente" button instead of silent retries.
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        localStoreProvider.overrideWithValue(localStore),
      ],
      child: const RankingBeachTennisApp(),
    ),
  );
}

/// On the web, the sign-in pages can be served from the site's own domain
/// (Firebase Hosting), which Safari handles better than a third-party domain.
FirebaseOptions _firebaseOptions() {
  final options = DefaultFirebaseOptions.currentPlatform;
  return kIsWeb && AppConfig.firebaseAuthDomain.isNotEmpty
      ? options.copyWith(authDomain: AppConfig.firebaseAuthDomain)
      : options;
}
