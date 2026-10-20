import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/features/about/app_info.dart';
import 'package:ranking_beach_tennis/features/auth/auth_providers.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/auth/firebase_auth_repository.dart';
import 'package:ranking_beach_tennis/features/auth/login_screen.dart';

import '../../helpers.dart';

void main() {
  late FakeAuthRepository auth;

  Future<void> pumpLogin(WidgetTester tester, {String? version = '1.1.2'}) async {
    auth = FakeAuthRepository();
    await pumpScreen(tester, const LoginScreen(), overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      appVersionProvider.overrideWith((ref) async => version),
    ]);
  }

  testWidgets('shows the app logo', (tester) async {
    await pumpLogin(tester);

    final logo = tester.widget<Image>(find.byType(Image));
    expect((logo.image as AssetImage).assetName, 'assets/branding/app_icon.png');
    expect(find.bySemanticsLabel('Logo do Ranking Beach Tennis'), findsOneWidget);
    expect(find.textContaining('Desenvolvido por'), findsNothing, reason: 'credit only in Sobre o app');
  });

  testWidgets('shows the app version in the footer', (tester) async {
    await pumpLogin(tester);
    await tester.pumpAndSettle();
    expect(find.text('Versão 1.1.2'), findsOneWidget);
  });

  testWidgets('without a known version the footer is empty', (tester) async {
    await pumpLogin(tester, version: null);
    await tester.pumpAndSettle();
    expect(find.textContaining('Versão'), findsNothing);
  });

  testWidgets('validates e-mail and password before calling the provider', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    expect(find.text('A senha deve ter pelo menos 6 caracteres.'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('signs in with e-mail and shows provider errors in Portuguese', (tester) async {
    await pumpLogin(tester);
    auth.failNextWith = AuthFailure(FirebaseAuthRepository.messageFor('invalid-credential'));

    await tester.enterText(find.byKey(const Key('email')), 'ana@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'secret1');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
    expect(auth.calls, ['email:ana@example.com']);
  });

  testWidgets('Enter in the password signs in', (tester) async {
    await pumpLogin(tester);

    await tester.enterText(find.byKey(const Key('email')), 'ana@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'secret1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(auth.calls, ['email:ana@example.com']);
  });

  testWidgets('registration asks for a display name', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Criar conta com e-mail'));
    await tester.pump();
    await tester.ensureVisible(find.text('Criar conta'));
    await tester.tap(find.text('Criar conta'));
    await tester.pump();

    expect(find.byKey(const Key('name')), findsOneWidget);
    expect(find.text('Como quer ser chamado'), findsOneWidget);
    expect(find.text('Informe nome e sobrenome.'), findsOneWidget);
    expect(find.text('Informe um nome entre 2 e 40 caracteres.'), findsOneWidget);
  });

  testWidgets('closing the Google picker is not an error', (tester) async {
    await pumpLogin(tester);
    auth.failNextWith = const AuthCancelled();

    await tester.tap(find.text('Entrar com Google'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['google']);
    expect(find.textContaining('Não foi possível'), findsNothing);
  });

  test('maps Firebase error codes to Portuguese messages', () {
    expect(FirebaseAuthRepository.messageFor('email-already-in-use'), 'Já existe uma conta com este e-mail.');
    expect(FirebaseAuthRepository.messageFor('weak-password'), 'Senha fraca: use pelo menos 6 caracteres.');
    expect(FirebaseAuthRepository.messageFor('something-new'), 'Não foi possível entrar. Tente novamente.');
  });
}
