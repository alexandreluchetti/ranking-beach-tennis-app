import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/push_registration.dart';
import 'auth_providers.dart';

/// Signs out after removing this device's push token, which needs the session
/// still valid.
final signOutProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await ref.read(pushRegistrationProvider.notifier).unregister();
    await ref.read(authRepositoryProvider).signOut();
  },
);
