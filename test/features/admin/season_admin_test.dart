import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/features/admin/admin_repository.dart';
import 'package:ranking_beach_tennis/features/admin/seasons_admin_screen.dart';
import 'package:ranking_beach_tennis/features/admin/season_form_screen.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_models.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';

import '../../helpers.dart';

void main() {
  final today = DateTime(2026, 10, 13);
  final planned = Season(
    id: 's2',
    name: 'Verão',
    startDate: DateTime(2027, 1, 1),
    endDate: DateTime(2027, 3, 31),
    status: SeasonStatus.planned,
  );
  final closed = Season(
    id: 's0',
    name: 'Inverno',
    startDate: DateTime(2026, 6, 1),
    endDate: DateTime(2026, 9, 30),
    status: SeasonStatus.closed,
  );

  late FakeAdminRepository admin;
  setUp(() => admin = FakeAdminRepository());

  Future<void> pumpAdmin(WidgetTester tester, {String location = '/profile/seasons'}) async {
    await initializeDateFormatting('pt_BR');
    final router = GoRouter(initialLocation: location, routes: [
      GoRoute(
        path: '/profile/seasons',
        builder: (_, _) => const SeasonsAdminScreen(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const SeasonFormScreen()),
          GoRoute(path: ':id', builder: (_, state) => SeasonFormScreen(seasonId: state.pathParameters['id']!)),
        ],
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'admin')), MemoryLocalStore()),
        adminRepositoryProvider.overrideWithValue(admin),
        todayProvider.overrideWithValue(today),
        seasonsProvider.overrideWith((ref) async => [planned, primavera, closed]),
        currentRankingProvider.overrideWith((ref) async => Cached(sampleRanking())),
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

  testWidgets('lists every season with its status; a closed one cannot be opened', (tester) async {
    await pumpAdmin(tester);

    expect(find.text('01/01/2027 a 31/03/2027 · Planejada'), findsOneWidget);
    expect(find.text('01/10/2026 a 31/12/2026 · Em andamento'), findsOneWidget);
    expect(find.text('01/06/2026 a 30/09/2026 · Encerrada'), findsOneWidget);

    await tester.tap(find.text('Inverno'));
    await tester.pumpAndSettle();
    expect(find.text('Editar temporada'), findsNothing);
  });

  testWidgets('creates a season, starting in the past if needed', (tester) async {
    await pumpAdmin(tester);
    await tester.tap(find.text('Nova temporada'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Criar temporada'));
    await tester.pumpAndSettle();
    expect(find.text('Use pelo menos 2 caracteres.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '  Primavera 2027 ');
    await tester.tap(find.text('Criar temporada'));
    await tester.pumpAndSettle();
    expect(find.text('Escolha as datas de início e de término.'), findsOneWidget);

    // Both pickers open on today; accept them.
    await tester.tap(find.byKey(const Key('startDate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('endDate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar temporada'));
    await tester.pumpAndSettle();

    expect(admin.calls, [
      {'op': 'create', 'name': 'Primavera 2027', 'startDate': today, 'endDate': today},
    ]);
    expect(find.text('Temporada criada.'), findsOneWidget);
    expect(find.text('Temporadas'), findsOneWidget);
  });

  testWidgets('a planned season sends only what changed', (tester) async {
    await pumpAdmin(tester, location: '/profile/seasons/s2');
    expect(find.text('Planejada'), findsOneWidget);
    expect(find.text('Encerrar hoje'), findsNothing);

    await tester.enterText(find.byType(TextFormField), 'Verão 2027');
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();

    expect(admin.calls, [
      {'op': 'update', 'id': 's2', 'name': 'Verão 2027'},
    ]);
  });

  testWidgets('an active season keeps its start date and can end today after confirmation', (tester) async {
    await pumpAdmin(tester, location: '/profile/seasons/s1');

    final start = tester.widget<ListTile>(find.byKey(const Key('startDate')));
    expect(start.enabled, isFalse);
    expect(find.text('Início (não muda com a temporada em andamento)'), findsOneWidget);

    await tester.tap(find.text('Encerrar hoje'));
    await tester.pumpAndSettle();
    expect(find.textContaining('uma temporada encerrada não pode ser reaberta'), findsOneWidget);
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(admin.calls, isEmpty);

    await tester.tap(find.text('Encerrar hoje'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Encerrar hoje'));
    await tester.pumpAndSettle();

    expect(admin.calls, [
      {'op': 'update', 'id': 's1', 'endDate': today},
    ]);
    expect(find.text('Temporada encerrada hoje.'), findsOneWidget);
  });

  testWidgets('shows the backend refusal and keeps the form', (tester) async {
    admin.errors.add(const ApiException(
      'Já existe uma temporada nesse período.',
      code: 'SEASON_OVERLAP',
      statusCode: 409,
    ));
    await pumpAdmin(tester, location: '/profile/seasons/s2');

    await tester.enterText(find.byType(TextFormField), 'Verão 2027');
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();

    expect(find.text('Já existe uma temporada nesse período.'), findsOneWidget);
    expect(find.text('Editar temporada'), findsOneWidget);
  });

  testWidgets('a closed season opened by link cannot be edited', (tester) async {
    await pumpAdmin(tester, location: '/profile/seasons/s0');

    expect(find.text('Esta temporada não pode ser alterada'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });
}
