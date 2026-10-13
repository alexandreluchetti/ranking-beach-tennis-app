import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/preferences.dart';
import 'package:ranking_beach_tennis/core/theme/theme_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('theme mode', () {
    Future<ProviderContainer> container(Map<String, Object> saved) async {
      SharedPreferences.setMockInitialValues(saved);
      final preferences = await SharedPreferences.getInstance();
      return ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(preferences)]);
    }

    test('follows the system by default', () async {
      expect((await container({})).read(themeModeProvider), ThemeMode.system);
    });

    test('remembers the chosen mode', () async {
      final first = await container({});
      await first.read(themeModeProvider.notifier).select(ThemeMode.dark);

      final preferences = await SharedPreferences.getInstance();
      final reopened = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(preferences)]);
      expect(reopened.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('API errors', () {
    final request = RequestOptions(path: '/api/matches');

    test('uses the Portuguese detail and code sent by the backend', () {
      final error = ApiException.fromDio(DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 400, data: {
          'code': 'INVALID_SCORE',
          'detail': 'Placar inválido para o formato escolhido.',
        }),
      ));

      expect(error.message, 'Placar inválido para o formato escolhido.');
      expect(error.code, 'INVALID_SCORE');
      expect(error.isNetworkError, isFalse);
    });

    test('explains connection problems', () {
      final error = ApiException.fromDio(DioException(requestOptions: request, type: DioExceptionType.connectionError));

      expect(error.isNetworkError, isTrue);
      expect(error.message, 'Sem conexão com o servidor. Verifique sua internet.');
    });

    test('expired sessions get a specific message', () {
      final error = ApiException.fromDio(DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 401),
      ));

      expect(error.message, 'Sua sessão expirou. Entre novamente.');
    });
  });
}
