import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/network/api_client.dart';
import 'package:ranking_beach_tennis/features/about/about_screen.dart';
import 'package:ranking_beach_tennis/features/about/app_info.dart';

import '../../helpers.dart';

/// Dio that answers /actuator/info with [body], or fails when [body] is null.
Dio _dioAnswering(Object? body, {int status = 200}) => Dio()
  ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    if (body == null) {
      handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError));
    } else {
      handler.resolve(Response(requestOptions: options, statusCode: status, data: body));
    }
  }));

void main() {
  testWidgets('shows the app version, the credits and an unavailable server version', (tester) async {
    await pumpScreen(tester, const AboutScreen(), overrides: [
      appVersionProvider.overrideWith((ref) async => '1.0.1'),
      backendVersionProvider.overrideWith((ref) async => null),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Versão do app'), findsOneWidget);
    expect(find.text('1.0.1'), findsOneWidget);
    expect(find.text('Versão do servidor'), findsOneWidget);
    expect(find.text('indisponível'), findsOneWidget);
    expect(find.text('Desenvolvido por Alexandre Lucchetta'), findsOneWidget);
    expect(find.text('Regras de pontuação'), findsOneWidget);
  });

  testWidgets('shows the server version when the backend exposes it', (tester) async {
    await pumpScreen(tester, const AboutScreen(), overrides: [
      appVersionProvider.overrideWith((ref) async => '1.1.0'),
      backendVersionProvider.overrideWith((ref) async => '1.0.0'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Versão do servidor'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
  });

  testWidgets('an unreadable app version shows as unavailable instead of loading forever', (tester) async {
    await pumpScreen(tester, const AboutScreen(), overrides: [
      appVersionProvider.overrideWith((ref) async => null),
      backendVersionProvider.overrideWith((ref) async => '1.0.1'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Versão do app'), findsOneWidget);
    expect(find.text('indisponível'), findsOneWidget);
    expect(find.text('…'), findsNothing);
  });

  test('app version text', () {
    expect(describeAppVersion('1.0.2'), '1.0.2', reason: 'no build number for people');
    expect(describeAppVersion(''), isNull);
  });

  group('server version', () {
    Future<String?> read(Dio dio) {
      final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
      addTearDown(container.dispose);
      return container.read(backendVersionProvider.future);
    }

    test('reads build.version from /actuator/info', () async {
      expect(await read(_dioAnswering({'build': {'version': '1.0.0', 'time': '2026-10-14T10:00:00Z'}})), '1.0.0');
    });

    test('is unknown when the backend does not expose it or is unreachable', () async {
      expect(await read(_dioAnswering(<String, dynamic>{})), isNull);
      expect(await read(_dioAnswering(null)), isNull);
    });
  });
}
