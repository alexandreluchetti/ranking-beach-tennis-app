import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/core/theme/app_theme.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/matches/match_draft.dart';
import 'package:ranking_beach_tennis/features/matches/match_history_screen.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/matches/match_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:ranking_beach_tennis/features/sync/pending_match.dart';
import 'package:ranking_beach_tennis/features/sync/sync_controller.dart';

import '../../helpers.dart';

void main() {
  testWidgets('lists matches with a clear status for each', (tester) async {
    final repository = FakeMatchRepository(matches: [
      sampleMatch(id: 'm1'),
      sampleMatch(id: 'm2', counted: false, reason: 'GUEST_PRESENT'),
      sampleMatch(id: 'm3', voided: true, counted: false, reason: 'VOIDED'),
    ]);
    await pumpScreen(tester, const MatchHistoryScreen(), leagues: null, overrides: [
      ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u-ana')), MemoryLocalStore()),
      matchRepositoryProvider.overrideWithValue(repository),
      seasonsProvider.overrideWith((ref) async => [primavera]),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Contabilizada'), findsOneWidget);
    expect(find.text('Não contabilizada: havia convidado'), findsOneWidget);
    expect(find.text('Anulada'), findsOneWidget);
    expect(find.text('Ana e Beto'), findsNWidgets(3));

    Color chipColor(String label) => ((tester
            .widget<Container>(find.ancestor(of: find.text(label), matching: find.byType(Container)).first)
            .decoration) as BoxDecoration)
        .color!;
    expect(chipColor('Contabilizada'), AppColors.successContainerLight);
    expect(chipColor('Anulada'), isNot(AppColors.successContainerLight));
    expect(find.text('Caio e Zé (convidado)'), findsNWidgets(3));
  });

  testWidgets('outcome filters are sent to the backend', (tester) async {
    final repository = FakeMatchRepository();
    await pumpScreen(tester, const MatchHistoryScreen(), leagues: null, overrides: [
      ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u-ana')), MemoryLocalStore()),
      matchRepositoryProvider.overrideWithValue(repository),
      seasonsProvider.overrideWith((ref) async => [primavera]),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma partida encontrada.'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Anuladas'));
    await tester.tap(find.widgetWithText(FilterChip, 'Anuladas'));
    await tester.pumpAndSettle();

    expect(repository.searches.last.outcomes, {MatchOutcome.voided});
    expect(find.text('Limpar'), findsOneWidget);
  });

  testWidgets('pending matches of the user appear on top with their sync status', (tester) async {
    final store = MemoryLocalStore();
    PendingMatch pending(String id, String owner, SyncStatus status, {String? message}) => PendingMatch(
          draft: MatchDraft(
            id: id,
            playedAt: DateTime(2026, 10, 11, 9, 30),
            format: MatchFormat.standard,
            positions: const [
              DraftPosition.player(PlayerSummary(id: 'p-ana', displayName: 'Ana')),
              DraftPosition.player(PlayerSummary(id: 'p-beto', displayName: 'Beto')),
              DraftPosition.player(PlayerSummary(id: 'p-caio', displayName: 'Caio')),
              DraftPosition.guest(),
            ],
            teamAGames: 6,
            teamBGames: 2,
          ),
          leagueId: 'l-arena',
          ownerUid: owner,
          status: status,
          message: message,
        );
    await store.write(SyncController.storageKey, [
      pending('a', 'u-ana', SyncStatus.pending).toStorage(),
      pending('b', 'u-ana', SyncStatus.failed, message: 'Placar inválido para o formato escolhido.').toStorage(),
      pending('c', 'u-beto', SyncStatus.pending).toStorage(),
    ]);
    final repository = FakeMatchRepository(matches: [sampleMatch()])..offline = true;
    await pumpScreen(tester, const MatchHistoryScreen(), leagues: null, overrides: [
      ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u-ana')), store),
      matchRepositoryProvider.overrideWithValue(repository),
      seasonsProvider.overrideWith((ref) async => [primavera]),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Pendentes de envio (2)'), findsOneWidget);
    expect(find.textContaining('Pendente de sincronização'), findsOneWidget);
    expect(find.textContaining('Erro de sincronização'), findsOneWidget);
    expect(find.textContaining('Placar inválido para o formato escolhido.'), findsOneWidget);
    expect(find.text('Contabilizada'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // disposes the scope and its retry timer
  });

  test('parses the backend match and its void information', () {
    final match = sampleMatch(voided: true, counted: false, reason: 'VOIDED');

    expect(match.voided, isTrue);
    expect(match.voidReason, 'Jogo de treino');
    expect(match.statusLabel, 'Anulada');
    expect(match.teamB[1].name, 'Zé (convidado)');
    expect(match.score, '6–4');
  });
}
