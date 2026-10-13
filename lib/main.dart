import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/local_store.dart';
import 'core/storage/preferences.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('pt_BR');
  final preferences = await SharedPreferences.getInstance();
  final localStore = FileLocalStore(await getApplicationSupportDirectory());
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
