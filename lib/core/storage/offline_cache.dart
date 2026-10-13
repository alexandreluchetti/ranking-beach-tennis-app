import '../network/api_exception.dart';
import 'local_store.dart';

/// Data plus, when it came from the device instead of the server, the moment
/// it was last fetched (so the screen can warn that it may be outdated).
class Cached<T> {
  const Cached(this.value, {this.savedAt});

  final T value;

  /// Null when the data is fresh from the server.
  final DateTime? savedAt;

  bool get fromCache => savedAt != null;
}

/// Fetches from the server and keeps a copy; without a connection, returns the
/// last copy instead. The server remains the source of truth.
Future<Cached<T>> fetchWithOfflineCopy<T>({
  required LocalStore store,
  required String key,
  required Future<T> Function() fetch,
  required Object? Function(T value) encode,
  required T Function(Object? json) decode,
  DateTime Function() now = DateTime.now,
}) async {
  try {
    final value = await fetch();
    await store.write(key, {'savedAt': now().toUtc().toIso8601String(), 'value': encode(value)});
    return Cached(value);
  } on ApiException catch (e) {
    final copy = store.readSync(key);
    if (!e.isNetworkError || copy is! Map<String, dynamic>) {
      rethrow;
    }
    return Cached(decode(copy['value']), savedAt: DateTime.parse(copy['savedAt'] as String).toLocal());
  }
}
