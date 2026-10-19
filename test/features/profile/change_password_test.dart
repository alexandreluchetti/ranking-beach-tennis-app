import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/core/storage/preferences.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/profile/change_password_screen.dart';
import 'package:ranking_beach_tennis/features/profile/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  late FakeAuthRepository auth;

  Future<void> pumpProfile(WidgetTester tester, {bool hasPassword = true}) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pt_BR');
    final preferences = await SharedPreferences.getInstance();
    auth = FakeAuthRepository(
      session: AuthSession(uid: 'u-ana', email: 'ana@example.com', hasPassword: hasPassword),
    );
    final router = GoRouter(initialLocation: '/profile', routes: [
      GoRoute(
        path: '/profile',
        builder: (_, _) => const ProfileScreen(),
        routes: [GoRoute(path: 'password', builder: (_, _) => const ChangePasswordScreen())],
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...deviceOverrides(auth, MemoryLocalStore()),
        sharedPreferencesProvider.overrideWithValue(preferences),
        meProvider.overrideWith((ref) async => anaMe),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, {String current = 'secret1', String next = 'novasenha', String? confirm}) async {
    await tester.enterText(find.byKey(const Key('currentPassword')), current);
    await tester.enterText(find.byKey(const Key('newPassword')), next);
    await tester.enterText(find.byKey(const Key('confirmNewPassword')), confirm ?? next);
    await tester.tap(find.widgetWithText(FilledButton, 'Alterar senha'));
    await tester.pumpAndSettle();
  }

  testWidgets('accounts signed in with Google have no password to change', (tester) async {
    await pumpProfile(tester, hasPassword: false);

    expect(find.text('Alterar senha'), findsNothing);
  });

  testWidgets('changes the password after confirming the current one', (tester) async {
    await pumpProfile(tester);
    await tester.tap(find.text('Alterar senha'));
    await tester.pumpAndSettle();

    await fill(tester, current: 'errada');
    expect(find.text('Senha atual incorreta.'), findsOneWidget);
    expect(auth.password, 'secret1');

    await fill(tester);

    expect(auth.password, 'novasenha');
    expect(find.text('Senha alterada.'), findsOneWidget);
    expect(find.byType(ChangePasswordScreen), findsNothing, reason: 'back to the profile');
  });

  testWidgets('checks the new password before calling Firebase', (tester) async {
    await pumpProfile(tester);
    await tester.tap(find.text('Alterar senha'));
    await tester.pumpAndSettle();

    await fill(tester, next: '123');
    expect(find.text('A senha deve ter pelo menos 6 caracteres.'), findsOneWidget);

    await fill(tester, confirm: 'outrasenha');
    expect(find.text('As senhas não coincidem.'), findsOneWidget);
    expect(auth.calls, isNot(contains('changePassword')));
  });

  testWidgets('"Esqueci minha senha atual" sends the reset e-mail to the account', (tester) async {
    await pumpProfile(tester);
    await tester.tap(find.text('Alterar senha'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Esqueci minha senha atual'));
    await tester.pumpAndSettle();

    expect(auth.calls, contains('reset:ana@example.com'));
    expect(find.text('Enviamos um e-mail para ana@example.com com o link para redefinir a senha.'), findsOneWidget);
  });
}
