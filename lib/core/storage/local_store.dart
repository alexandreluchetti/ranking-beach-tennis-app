import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Small JSON documents kept on the device (pending matches, offline caches).
abstract class LocalStore {
  Object? readSync(String name);

  Future<void> write(String name, Object? value);
}

/// One file per document. Writes go to a temporary file first and are then
/// renamed, so an interrupted write never leaves a half-written document.
class FileLocalStore implements LocalStore {
  FileLocalStore(this.directory);

  final Directory directory;

  File _file(String name) => File('${directory.path}${Platform.pathSeparator}$name.json');

  @override
  Object? readSync(String name) {
    final file = _file(name);
    if (!file.existsSync()) {
      return null;
    }
    try {
      return jsonDecode(file.readAsStringSync());
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String name, Object? value) async {
    await directory.create(recursive: true);
    final target = _file(name);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(target.path);
  }
}

/// Created in `main` (app support directory) and injected with an override.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('Override localStoreProvider in main'),
);
