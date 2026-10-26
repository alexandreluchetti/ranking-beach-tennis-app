import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/read_cache.dart';
import '../notifications/push_registration.dart';
import 'auth_providers.dart';

/// Signs out after removing this device's push token, which needs the session
/// still valid.
final signOutProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await ref.read(pushRegistrationProvider.notifier).unregister();
    // Nothing of this account stays on the device for the next one.
    await ref.read(readCacheProvider)?.clearUser();
    await ref.read(authRepositoryProvider).signOut();
  },
);
