import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/network/api_client.dart';

/// Version of this app as shown to people, e.g. "1.0.1 (build 2)".
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty ? info.version : '${info.version} (build ${info.buildNumber})';
});

/// Backend version from `GET /actuator/info` (`build.version`), or null when
/// the backend does not expose it or cannot be reached.
final backendVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final response = await ref.watch(dioProvider).get<Map<String, dynamic>>('/actuator/info');
    final build = response.data?['build'];
    final version = build is Map ? build['version'] : null;
    return version is String && version.isNotEmpty ? version : null;
  } catch (_) {
    return null;
  }
});
