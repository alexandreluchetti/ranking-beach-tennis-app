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
  final saved = <String>[];
  bool offline = false;

  @override
  Future<Me> load() async => current;

  @override
  Future<Me> updateDisplayName(String name) async {
    if (offline) {
      throw const ApiException('Sem conexão com o servidor. Verifique sua internet.');
    }
    saved.add(name);
    return current = Me(id: current.id, displayName: name, email: current.email, admin: false);
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

  setUp(() {
    store = MemoryLocalStore();
    me = _FakeMeRepository();
  });

  test('the name typed when creating the account replaces the one from the e-mail', () async {
    await PendingDisplayName.save(store, email: 'teste@gmail.com', name: '  Alex  ');

    final loaded = await open().read(meProvider.future);

    expect(loaded!.displayName, 'Alex');
    expect(me.saved, ['Alex']);
    expect(store.readSync(PendingDisplayName.storageKey), isNull, reason: 'confirmed by the backend');
  });

  test('without a connection the name is kept and sent on the next start', () async {
    await PendingDisplayName.save(store, email: 'teste@gmail.com', name: 'Alex');
    me.offline = true;

    expect((await open().read(meProvider.future))!.displayName, 'teste');
    expect(store.readSync(PendingDisplayName.storageKey), isNotNull);

    me.offline = false;
    expect((await open().read(meProvider.future))!.displayName, 'Alex');
    expect(store.readSync(PendingDisplayName.storageKey), isNull);
  });

  test('a name typed for another account is not applied', () async {
    await PendingDisplayName.save(store, email: 'outra@gmail.com', name: 'Alex');

    expect((await open().read(meProvider.future))!.displayName, 'teste');
    expect(me.saved, isEmpty);
  });

  test('nothing is sent when the backend already has the name', () async {
    await PendingDisplayName.save(store, email: 'teste@gmail.com', name: 'teste');

    await open().read(meProvider.future);

    expect(me.saved, isEmpty);
    expect(store.readSync(PendingDisplayName.storageKey), isNull);
  });

  testWidgets('creating an account with e-mail keeps the typed name for the backend', (tester) async {
    final auth = FakeAuthRepository();
    await pumpScreen(tester, const LoginScreen(), leagues: null, overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      localStoreProvider.overrideWithValue(store),
    ]);

    await tester.tap(find.text('Criar conta com e-mail'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('name')), ' Alex   Souza ');
    await tester.enterText(find.byKey(const Key('email')), 'Teste@gmail.com');
    await tester.enterText(find.byKey(const Key('password')), 'secret1');
    await tester.tap(find.text('Criar conta'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['register:Alex Souza:Teste@gmail.com']);
    expect(store.readSync(PendingDisplayName.storageKey), {'email': 'teste@gmail.com', 'name': 'Alex Souza'});
  });
}
