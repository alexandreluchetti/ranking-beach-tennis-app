import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/local_store.dart';
import 'package:ranking_beach_tennis/features/auth/auth_providers.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/auth/login_screen.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';

import '../../helpers.dart';

/// The backend created the profile from the e-mail (no name in the first token).
class _FakeMeRepository implements MeRepository {
  Me current = const Me(id: 'p-new', displayName: 'teste', email: 'teste@gmail.com', admin: false);
  final saved = <Map<String, String?>>[];
  bool offline = false;

  @override
  Future<Me> load() async => current;

  @override
  Future<Me> updateNames({String? displayName, String? fullName}) async {
    if (offline) {
      throw const ApiException('Sem conexão com o servidor. Verifique sua internet.');
    }
    saved.add({'displayName': displayName, 'fullName': fullName});
    return current = Me(
      id: current.id,
      displayName: displayName ?? current.displayName,
      fullName: fullName ?? current.fullName,
      email: current.email,
      admin: false,
    );
  }

  @override
  Future<GlobalStats> statistics() async => noStatistics;
}

void main() {
  late MemoryLocalStore store;
  late _FakeMeRepository me;

  ProviderContainer open({String email = 'Teste@Gmail.com'}) {
    final container = ProviderContainer(overrides: [
      ...deviceOverrides(FakeAuthRepository(session: AuthSession(uid: 'u-new', email: email)), store),
      meRepositoryProvider.overrideWithValue(me),
    ]);
    addTearDown(container.dispose);
    // Providers without listeners are paused.
    container.listen(meProvider, (_, _) {});
    return container;
  }

  Future<void> savePending({String email = 'teste@gmail.com', String displayName = 'Alex'}) =>
      PendingProfileNames.save(store, email: email, displayName: displayName, fullName: ' Alexandre   Lucchetta ');

  setUp(() {
    store = MemoryLocalStore();
    me = _FakeMeRepository();
  });

  test('the names typed when creating the account replace the one from the e-mail', () async {
    await savePending(displayName: '  Alex  ');

    final loaded = await open().read(meProvider.future);

    expect(loaded!.displayName, 'Alex');
    expect(loaded.fullName, 'Alexandre Lucchetta');
    expect(me.saved, [
      {'displayName': 'Alex', 'fullName': 'Alexandre Lucchetta'},
    ]);
    expect(store.readSync(PendingProfileNames.storageKey), isNull, reason: 'confirmed by the backend');
  });

  test('without a connection the names are kept and sent on the next start', () async {
    await savePending();
    me.offline = true;

    expect((await open().read(meProvider.future))!.displayName, 'teste');
    expect(store.readSync(PendingProfileNames.storageKey), isNotNull);

    me.offline = false;
    expect((await open().read(meProvider.future))!.displayName, 'Alex');
    expect(store.readSync(PendingProfileNames.storageKey), isNull);
  });

  test('names typed for another account are not applied', () async {
    await savePending(email: 'outra@gmail.com');

    expect((await open().read(meProvider.future))!.displayName, 'teste');
    expect(me.saved, isEmpty);
  });

  test('only the names that differ are sent', () async {
    me.current = const Me(id: 'p-new', displayName: 'Alex', email: 'teste@gmail.com', admin: false);
    await savePending();

    await open().read(meProvider.future);

    expect(me.saved, [
      {'displayName': null, 'fullName': 'Alexandre Lucchetta'},
    ]);
  });

  test('the full name needs name and surname', () {
    expect(validateFullName('Alexandre'), 'Informe nome e sobrenome.');
    expect(validateFullName('  A  '), 'Informe nome e sobrenome.');
    expect(validateFullName('Alexandre   Lucchetta'), isNull);
    expect(validateFullName('A B'), isNull);
    expect(validateFullName('A ${'b' * 99}'), 'Informe nome e sobrenome.', reason: 'over 100 characters');
  });

  group('creating an account with e-mail', () {
    late FakeAuthRepository auth;

    Future<void> fillAndSubmit(
      WidgetTester tester, {
      String fullName = 'Alexandre  Lucchetta',
      String name = ' Alex ',
      String confirm = 'secret1',
    }) async {
      auth = FakeAuthRepository();
      await pumpScreen(tester, const LoginScreen(), leagues: null, overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        localStoreProvider.overrideWithValue(store),
      ]);
      await tester.tap(find.text('Criar conta com e-mail'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('fullName')), fullName);
      await tester.enterText(find.byKey(const Key('name')), name);
      await tester.enterText(find.byKey(const Key('email')), 'Teste@gmail.com');
      await tester.enterText(find.byKey(const Key('password')), 'secret1');
      await tester.enterText(find.byKey(const Key('confirmPassword')), confirm);
      await tester.ensureVisible(find.text('Criar conta'));
      await tester.tap(find.text('Criar conta'));
      await tester.pumpAndSettle();
    }

    testWidgets('keeps both typed names for the backend', (tester) async {
      await fillAndSubmit(tester);

      expect(auth.calls, ['register:Alex:Teste@gmail.com']);
      expect(store.readSync(PendingProfileNames.storageKey), {
        'email': 'teste@gmail.com',
        'displayName': 'Alex',
        'fullName': 'Alexandre Lucchetta',
      });
    });

    testWidgets('a full name with one word blocks the sign-up', (tester) async {
      await fillAndSubmit(tester, fullName: 'Alexandre');

      expect(find.text('Informe nome e sobrenome.'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('different passwords block the sign-up', (tester) async {
      await fillAndSubmit(tester, confirm: 'secret2');

      expect(find.text('As senhas não coincidem.'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });
  });
}
