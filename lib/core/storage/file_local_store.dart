import 'dart:convert';
import 'dart:io';

import 'local_store.dart';

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

  @override
  Future<void> delete(String name) async {
    final file = _file(name);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  @override
  Iterable<String> names() {
    if (!directory.existsSync()) {
      return const [];
    }
    return [
      for (final entity in directory.listSync())
        if (entity is File && entity.path.endsWith('.json'))
          entity.uri.pathSegments.last.substring(0, entity.uri.pathSegments.last.length - '.json'.length),
    ];
  }
}
