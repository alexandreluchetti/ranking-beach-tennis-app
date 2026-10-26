/// The answer of a read that may have come from the device (see `cachedRead`
/// in read_cache.dart); the notice about outdated data is app-wide
/// (`outdatedDataProvider`).
class Cached<T> {
  const Cached(this.value);

  final T value;
}
