import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small JSON documents kept on the device (pending matches, offline caches).
abstract class LocalStore {
  Object? readSync(String name);

  Future<void> write(String name, Object? value);
}

/// One SharedPreferences entry per document. Used on the web, where it is
/// backed by the browser's local storage.
class PreferencesLocalStore implements LocalStore {
  PreferencesLocalStore(this._preferences);

  static const _prefix = 'store.';

  final SharedPreferences _preferences;

  @override
  Object? readSync(String name) {
    final raw = _preferences.getString('$_prefix$name');
    if (raw == null) {
      return null;
    }
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String name, Object? value) async {
    await _preferences.setString('$_prefix$name', jsonEncode(value));
  }
}

/// Created in `main` (see [openLocalStore]) and injected with an override.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('Override localStoreProvider in main'),
);
