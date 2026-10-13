import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A push message the user tapped, with the data sent by the backend.
class PushOpened {
  const PushOpened({this.notificationId, this.matchId});

  factory PushOpened.fromData(Map<String, dynamic> data) {
    String? value(String key) {
      final v = data[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    return PushOpened(notificationId: value('notificationId'), matchId: value('matchId'));
  }

  final String? notificationId;
  final String? matchId;
}

/// Push messaging port. The only implementation is Firebase Cloud Messaging;
/// tests use a fake so they never reach Firebase.
abstract class PushMessaging {
  /// Asks the user to allow notifications (Android 13+ and iOS). Denying is
  /// fine: the app keeps working, just without push.
  Future<void> requestPermission();

  /// This installation's token, or null when it cannot be obtained now.
  Future<String?> token();

  Stream<String> get tokenRefreshes;

  /// A push arrived while the app was in the foreground.
  Stream<void> get foregroundMessages;

  /// The user tapped a push while the app was running in the background.
  Stream<PushOpened> get openedMessages;

  /// The push the user tapped to launch the app, if any.
  Future<PushOpened?> initialMessage();
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<void> requestPermission() async {
    await _messaging.requestPermission();
  }

  @override
  Future<String?> token() async {
    try {
      return await _messaging.getToken();
    } catch (_) {
      // No connection or Google Play services unavailable; tried again later.
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<void> get foregroundMessages => FirebaseMessaging.onMessage.map((_) {});

  @override
  Stream<PushOpened> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp.map((message) => PushOpened.fromData(message.data));

  @override
  Future<PushOpened?> initialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : PushOpened.fromData(message.data);
  }
}

final pushMessagingProvider =
    Provider<PushMessaging>((ref) => FirebasePushMessaging(FirebaseMessaging.instance));
