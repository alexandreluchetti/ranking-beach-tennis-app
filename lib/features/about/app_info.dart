import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/network/api_client.dart';

/// Shown in "Sobre o app" and on the sign-in screen.
const appDeveloper = 'Alexandre Lucchetta';

/// "1.0.2", or null when unknown. The build number is not shown to people.
String? describeAppVersion(String version) => version.isEmpty ? null : version;

/// Reads `version.json` next to the web app, the file package_info_plus reads.
final webVersionFileProvider = Provider<Future<Map<String, dynamic>?> Function()>(
  (ref) => () async {
    try {
      final url = Uri.base.resolve('/version.json').replace(
        queryParameters: {'v': '${DateTime.now().millisecondsSinceEpoch}'},
      );
      final response = await Dio().getUri<Map<String, dynamic>>(url);
      return response.data;
    } catch (_) {
      return null;
    }
  },
);

/// Version of this app as shown to people, or null when it cannot be read.
///
/// On the web, package_info_plus 10.2.2 fails with the site's `<base href="/">`
/// (it builds the version.json URL without a scheme), so the file is read here.
final appVersionProvider = FutureProvider<String?>((ref) async {
  var version = '';
  try {
    version = (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    // Handled below.
  }
  if (version.isEmpty && kIsWeb) {
    final file = await ref.read(webVersionFileProvider)();
    version = file?['version'] as String? ?? '';
  }
  return describeAppVersion(version);
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
