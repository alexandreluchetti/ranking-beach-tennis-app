import 'package:shared_preferences/shared_preferences.dart';

import 'local_store.dart';
import 'open_local_store_io.dart' if (dart.library.js_interop) 'open_local_store_web.dart' as platform;

/// Files in the app support directory on Android and iOS; the browser's
/// local storage on the web.
Future<LocalStore> openLocalStore(SharedPreferences preferences) => platform.openLocalStore(preferences);
