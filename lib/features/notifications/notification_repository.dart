import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

/// In-app notification about a match. Title and body come written in pt-BR by
/// the backend, identical to the push message.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    this.matchId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        type: json['type'] as String,
        matchId: json['matchId'] as String?,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        read: json['read'] as bool,
      );

  final String id;

  /// MATCH_REGISTERED, MATCH_CORRECTED, MATCH_VOIDED or MATCH_VOID_REVERTED.
  final String type;
  final String? matchId;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  AppNotification markedRead() => AppNotification(
        id: id,
        type: type,
        matchId: matchId,
        title: title,
        body: body,
        createdAt: createdAt,
        read: true,
      );
}

class NotificationPage {
  const NotificationPage({required this.items, required this.unreadCount, required this.hasNext});

  final List<AppNotification> items;
  final int unreadCount;
  final bool hasNext;
}

enum DevicePlatform { android, ios }

class NotificationRepository {
  NotificationRepository(this._dio);

  final Dio _dio;

  /// Most recent first, with the total of unread notifications.
  Future<NotificationPage> list({int page = 0, int size = 20}) => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/notifications',
          queryParameters: {'page': page, 'size': size},
        );
        final data = response.data!;
        return NotificationPage(
          items: (data['items'] as List).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList(),
          unreadCount: data['unreadCount'] as int,
          hasNext: data['hasNext'] as bool,
        );
      });

  Future<void> markRead(String id) => apiCall(() => _dio.post<void>('/api/notifications/$id/read'));

  Future<void> markAllRead() => apiCall(() => _dio.post<void>('/api/notifications/read-all'));

  /// Registers (or moves to the signed-in player) this device's push token.
  Future<void> registerDevice(String token, DevicePlatform platform) => apiCall(
        () => _dio.put<void>('/api/me/devices', data: {'token': token, 'platform': platform.name.toUpperCase()}),
      );

  Future<void> unregisterDevice(String token) =>
      apiCall(() => _dio.delete<void>('/api/me/devices/${Uri.encodeComponent(token)}'));
}

final notificationRepositoryProvider =
    Provider<NotificationRepository>((ref) => NotificationRepository(ref.watch(dioProvider)));
