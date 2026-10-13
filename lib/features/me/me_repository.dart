import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_providers.dart';

/// The signed-in player's profile on the backend.
class Me {
  const Me({required this.id, required this.displayName, this.email, required this.admin});

  factory Me.fromJson(Map<String, dynamic> json) => Me(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        email: json['email'] as String?,
        admin: json['admin'] as bool,
      );

  final String id;
  final String displayName;
  final String? email;
  final bool admin;
}

class MeRepository {
  MeRepository(this._dio);

  final Dio _dio;

  /// Also creates the profile on first access, which puts the player in the ranking.
  Future<Me> load() => apiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>('/api/me');
        return Me.fromJson(response.data!);
      });

  Future<Me> updateDisplayName(String name) => apiCall(() async {
        final response = await _dio.patch<Map<String, dynamic>>('/api/me', data: {'displayName': name});
        return Me.fromJson(response.data!);
      });
}

final meRepositoryProvider = Provider<MeRepository>((ref) => MeRepository(ref.watch(dioProvider)));

/// Reloaded whenever the signed-in user changes.
final meProvider = FutureProvider<Me?>((ref) async {
  final session = await ref.watch(sessionProvider.future);
  if (session == null) {
    return null;
  }
  return ref.watch(meRepositoryProvider).load();
});
