import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

/// In-app notification about a match or a league. Title and body come written
/// in pt-BR by the backend, identical to the push message.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    this.matchId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.leagueId,
    this.joinRequestId,
    this.invitationId,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        type: json['type'] as String,
        matchId: json['matchId'] as String?,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        read: json['read'] as bool,
        leagueId: json['leagueId'] as String?,
        joinRequestId: json['joinRequestId'] as String?,
        invitationId: json['invitationId'] as String?,
      );

  final String id;

  /// MATCH_REGISTERED, MATCH_CORRECTED, MATCH_VOIDED, MATCH_VOID_REVERTED,
  /// LEAGUE_JOIN_REQUESTED, LEAGUE_JOIN_REQUEST_ACCEPTED,
  /// LEAGUE_JOIN_REQUEST_REJECTED or LEAGUE_INVITATION_RECEIVED.
  final String type;
  final String? matchId;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  /// League of the match or of the league event.
  final String? leagueId;

  /// Join request an administrator may answer (LEAGUE_JOIN_REQUESTED).
  final String? joinRequestId;

  /// Invitation the user may accept or reject (LEAGUE_INVITATION_RECEIVED).
  final String? invitationId;

  AppNotification markedRead() => AppNotification(
        id: id,
        type: type,
        matchId: matchId,
        title: title,
        body: body,
        createdAt: createdAt,
        read: true,
        leagueId: leagueId,
        joinRequestId: joinRequestId,
        invitationId: invitationId,
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

  /// Deletes one notification for good (D-032). Already gone (e.g. resent after
  /// a network failure) counts as done.
  Future<void> delete(String id) async {
    try {
      await apiCall(() => _dio.delete<void>('/api/notifications/$id'));
    } on ApiException catch (e) {
      if (e.code != 'NOTIFICATION_NOT_FOUND') {
        rethrow;
      }
    }
  }

  /// Deletes several, up to [batchSize] per request; unknown ids are ignored.
  Future<void> deleteMany(List<String> ids) async {
    for (var i = 0; i < ids.length; i += batchSize) {
      final batch = ids.sublist(i, i + batchSize > ids.length ? ids.length : i + batchSize);
      await apiCall(() => _dio.post<void>('/api/notifications/delete', data: {'ids': batch}));
    }
  }

  /// Deletes every notification of the user.
  Future<void> deleteAll() => apiCall(() => _dio.delete<void>('/api/notifications'));

  /// The most ids the backend takes in one batch delete.
  static const batchSize = 100;

  /// Registers (or moves to the signed-in player) this device's push token.
  Future<void> registerDevice(String token, DevicePlatform platform) => apiCall(
        () => _dio.put<void>('/api/me/devices', data: {'token': token, 'platform': platform.name.toUpperCase()}),
      );

  Future<void> unregisterDevice(String token) =>
      apiCall(() => _dio.delete<void>('/api/me/devices/${Uri.encodeComponent(token)}'));
}

final notificationRepositoryProvider =
    Provider<NotificationRepository>((ref) => NotificationRepository(ref.watch(dioProvider)));
