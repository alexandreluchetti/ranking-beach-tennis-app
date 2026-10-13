import 'package:shared_preferences/shared_preferences.dart';

import 'local_store.dart';

Future<LocalStore> openLocalStore(SharedPreferences preferences) async => PreferencesLocalStore(preferences);
