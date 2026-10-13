import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_local_store.dart';
import 'local_store.dart';

Future<LocalStore> openLocalStore(SharedPreferences preferences) async =>
    FileLocalStore(await getApplicationSupportDirectory());
