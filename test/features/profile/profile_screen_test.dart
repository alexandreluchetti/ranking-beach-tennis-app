import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/preferences.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/profile/display_name_dialog.dart';
import 'package:ranking_beach_tennis/features/profile/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

class _FakeMeRepository implements MeRepository {
  Me current = anaMe;
  /// Display names sent, in order.
  final saved = <String>[];
  final savedFullNames = <String>[];
  ApiException? failNextWith;

  @override
  Future<Me> load() async => current;

  @override
  Future<GlobalStats> statistics() async => noStatistics;

  @override
  Future<Me> updateNames({String? displayName, String? fullName}) async {
    final failure = failNextWith;
    if (failure != null) {
      failNextWith = null;
      throw failure;
    }
    if (displayName != null) saved.add(displayName);
    if (fullName != null) savedFullNames.add(fullName);
    current = Me(
      id: current.id,
      displayName: displayName ?? current.displayName,
      fullName: fullName ?? current.fullName,
      email: current.email,
      admin: current.admin,
    );
    return current;
  }
}

void main() {
  late _FakeMeRepository me;

  Future<void> pumpProfile(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await pumpScreen(tester, const ProfileScreen(), leagues: null, overrides: [
      ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u-ana')), MemoryLocalStore()),
      sharedPreferencesProvider.overrideWithValue(preferences),
      meRepositoryProvider.overrideWithValue(me),
    ]);
    await tester.pumpAndSettle();
  }

  setUp(() => me = _FakeMeRepository());

  test('display names follow the backend rule', () {
    expect(normalizeDisplayName('  Ana   Maria \n Souza '), 'Ana Maria Souza');
    expect(validateDisplayName(' A '), isNotNull);
    expect(validateDisplayName('Al'), isNull);
    expect(validateDisplayName('a' * 40), isNull);
    expect(validateDisplayName('a' * 41), isNotNull);
  });

  testWidgets('changes the display name', (tester) async {
    await pumpProfile(tester);
    expect(find.text('Ana'), findsOneWidget);

    await tester.tap(find.byTooltip('Editar nomes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('displayName')), '  Ana   Paula ');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(me.saved, ['Ana Paula']);
    expect(me.savedFullNames, isEmpty, reason: 'only what changed is sent');
    expect(find.text('Nome atualizado.'), findsOneWidget);
    expect(find.text('Ana Paula'), findsOneWidget);
  });

  testWidgets('rejects a name that is too short without calling the backend', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.byTooltip('Editar nomes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('displayName')), 'A');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Use pelo menos 2 caracteres.'), findsOneWidget);
    expect(me.saved, isEmpty);
  });

  testWidgets('shows the backend error and keeps the dialog open', (tester) async {
    me.failNextWith = const ApiException('Sem conexão com o servidor. Verifique sua internet.');
    await pumpProfile(tester);

    await tester.tap(find.byTooltip('Editar nomes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('displayName')), 'Ana Paula');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Sem conexão com o servidor. Verifique sua internet.'), findsOneWidget);
    expect(find.text('Seus nomes'), findsOneWidget);
  });

  testWidgets('one block with both names and the e-mail, edited by a single button', (tester) async {
    await pumpProfile(tester);
    expect(find.text('Ana Souza\nana@example.com'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);

    await tester.tap(find.byTooltip('Editar nomes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fullName')), 'Ana');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe nome e sobrenome.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('fullName')), 'Ana  Paula Souza');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(me.savedFullNames, ['Ana Paula Souza']);
    expect(me.saved, isEmpty);
    expect(find.text('Ana Paula Souza\nana@example.com'), findsOneWidget);
  });
}
