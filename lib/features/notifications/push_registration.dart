import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/preferences.dart';
import '../auth/auth_providers.dart';
import 'notification_repository.dart';
import 'push_messaging.dart';

/// Keeps this device's push token registered for the signed-in player.
/// State: the token the backend knows about, or null while not registered.
///
/// After the first sign-in on the device the user is asked once to allow
/// notifications; the token is registered whether or not they allow it, so
/// enabling notifications later in the phone settings is enough.
class PushRegistration extends Notifier<String?> {
  static const permissionAskedKey = 'notification_permission_asked';

  bool _signedIn = false;

  @override
  String? build() {
    ref.listen(sessionProvider, (_, next) {
      final signedIn = next.value != null;
      if (signedIn && !_signedIn) {
        unawaited(register());
      }
      _signedIn = signedIn;
    }, fireImmediately: true);
    final refreshes = ref.read(pushMessagingProvider).tokenRefreshes.listen((token) {
      if (_signedIn) {
        unawaited(_send(token));
      }
    });
    ref.onDispose(refreshes.cancel);
    return null;
  }

  /// Asks for permission the first time, then sends the token. Failures (e.g.
  /// offline) are ignored; it is tried again when the app returns to the
  /// foreground.
  Future<void> register() async {
    if (kIsWeb) {
      return; // No push on the web (see NoPushMessaging).
    }
    final preferences = ref.read(sharedPreferencesProvider);
    final messaging = ref.read(pushMessagingProvider);
    if (!(preferences.getBool(permissionAskedKey) ?? false)) {
      await preferences.setBool(permissionAskedKey, true);
      try {
        await messaging.requestPermission();
      } catch (_) {
        // The app works without push.
      }
    }
    final token = await messaging.token();
    if (token != null) {
      await _send(token);
    }
  }

  /// Registers again if the last attempt did not reach the backend.
  Future<void> ensureRegistered() async {
    if (_signedIn && state == null) {
      await register();
    }
  }

  /// Stops push to this device for the current player. Must run before the
  /// Firebase sign-out, while requests are still authenticated. Best effort: if
  /// it fails, the token moves to whoever signs in next on this device.
  Future<void> unregister() async {
    final token = state ?? await ref.read(pushMessagingProvider).token();
    state = null;
    if (token == null) {
      return;
    }
    try {
      await ref.read(notificationRepositoryProvider).unregisterDevice(token).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Signing out must never be blocked by this.
    }
  }

  Future<void> _send(String token) async {
    try {
      await ref.read(notificationRepositoryProvider).registerDevice(token, _platform);
      state = token;
    } catch (_) {
      state = null;
    }
  }

  static DevicePlatform get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? DevicePlatform.ios : DevicePlatform.android;
}

final pushRegistrationProvider = NotifierProvider<PushRegistration, String?>(PushRegistration.new);
