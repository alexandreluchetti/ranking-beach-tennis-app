import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ranking_beach_tennis/core/network/api_exception.dart';
import 'package:ranking_beach_tennis/core/storage/offline_cache.dart';
import 'package:ranking_beach_tennis/features/admin/admin_repository.dart';
import 'package:ranking_beach_tennis/features/auth/auth_repository.dart';
import 'package:ranking_beach_tennis/features/leagues/league_models.dart';
import 'package:ranking_beach_tennis/features/leagues/league_repository.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';
import 'package:ranking_beach_tennis/features/me/me_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_models.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_repository.dart';
import 'package:ranking_beach_tennis/features/ranking/ranking_screen.dart';
import 'package:ranking_beach_tennis/features/tournament/stage_attendance_screen.dart';
import 'package:ranking_beach_tennis/features/tournament/stage_models.dart';
import 'package:ranking_beach_tennis/features/tournament/stage_repository.dart';
import 'package:ranking_beach_tennis/features/tournament/stage_screen.dart';

import '../../helpers.dart';

const _names = ['Ana', 'Beto', 'Caio', 'Dani', 'Edu', 'Fabi', 'Gil', 'Hugo'];

/// 8 players, 4 pairs in one group (round robin in rounds, then the
/// knockout). Pair 1 (Ana and Beto) beat pair 2 in game 1 (round 1). A
/// finished stage had semifinals, the 3rd place game and the final (D-030).
Map<String, dynamic> stageJson({
  bool canEnterScores = true,
  bool canAdminister = false,
  bool finished = false,
  bool knockoutDrawn = false,
}) =>
    {
      'id': 'st1',
      'seasonId': 's-t',
      'date': '2026-11-06',
      'format': 'STANDARD',
      'knockoutDrawn': knockoutDrawn || finished,
      'finished': finished,
      'canEnterScores': canEnterScores,
      'canAdminister': canAdminister,
      'players': [
        for (final (i, name) in _names.indexed)
          i == 7
              ? {'position': 8, 'playerId': null, 'displayName': null, 'guestName': name}
              : {'position': i + 1, 'playerId': 'p-${name.toLowerCase()}', 'displayName': name, 'guestName': null},
      ],
      'pairs': [
        for (var n = 1; n <= 4; n++)
          {
            'number': n,
            'group': 1,
            'players': [2 * n - 1, 2 * n],
            'placement': finished ? const ['CHAMPION', 'RUNNER_UP', 'THIRD', 'FOURTH'][n - 1] : null,
          },
      ],
      'groups': [
        {
          'group': 1,
          'standings': [
            for (final pair in const [1, 3, 4, 2])
              {'pair': pair, 'played': 1, 'wins': pair == 1 ? 1 : 0, 'gamesWon': 6, 'gamesLost': 3, 'gameDifference': 3},
          ],
        },
      ],
      'fixtures': [
        {
          'number': 1,
          'round': 'GROUP',
          'group': 1,
          'groupRound': 1,
          'pairA': 1,
          'pairB': 2,
          'score': {
            'matchId': 'm-1',
            'matchVersion': 2,
            'teamAGames': 6,
            'teamBGames': 3,
            'tiebreakTeamAPoints': null,
            'tiebreakTeamBPoints': null,
          },
        },
        {'number': 2, 'round': 'GROUP', 'group': 1, 'groupRound': 1, 'pairA': 3, 'pairB': 4, 'score': null},
        {'number': 3, 'round': 'GROUP', 'group': 1, 'groupRound': 2, 'pairA': 1, 'pairB': 3, 'score': null},
        if (finished) ...[
          {'number': 7, 'round': 'THIRD_PLACE', 'group': null, 'groupRound': null, 'pairA': 3, 'pairB': 4, 'score': _won},
          {'number': 8, 'round': 'FINAL', 'group': null, 'groupRound': null, 'pairA': 1, 'pairB': 2, 'score': _won},
        ] else if (knockoutDrawn)
          {'number': 8, 'round': 'FINAL', 'group': null, 'groupRound': null, 'pairA': 1, 'pairB': 2, 'score': null},
      ],
    };

const _won = {
  'matchId': 'm-x',
  'matchVersion': 1,
  'teamAGames': 6,
  'teamBGames': 2,
  'tiebreakTeamAPoints': null,
  'tiebreakTeamBPoints': null,
};

/// Stages answered from memory; records every call.
class FakeStageRepository implements StageRepository {
  FakeStageRepository(this.stage);

  Stage stage;
  final calls = <String>[];
  final errors = <ApiException>[];
  List<StageAttendee>? created;

  Future<Stage> _answer(String call) async {
    calls.add(call);
    if (errors.isNotEmpty) {
      throw errors.removeAt(0);
    }
    return stage;
  }

  @override
  Future<Stage> byId(String id) async => stage;

  @override
  Future<List<StageSummary>> list() async => [StageSummary.fromJson({...stage.toJson(), 'playerCount': stage.players.length})];

  @override
  Future<Stage> score(String id, int number,
          {required int teamAGames,
          required int teamBGames,
          int? tiebreakTeamAPoints,
          int? tiebreakTeamBPoints,
          int? expectedMatchVersion,
          String? reason}) =>
      _answer('score:$number:$teamAGames-$teamBGames:${expectedMatchVersion ?? '-'}');

  @override
  Future<Stage> reopenGroups(String id) => _answer('reopen');

  @override
  Future<Stage> create({required MatchFormat format, required List<StageAttendee> players, DateTime? date}) {
    created = players;
    return _answer('create:${format.apiValue}:${players.length}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _tournament = Season(
  id: 's-t',
  name: 'Torneio',
  startDate: DateTime(2026, 11, 1),
  endDate: DateTime(2026, 12, 31),
  status: SeasonStatus.active,
  rankingType: RankingType.dailyTournament,
  placementPoints: PlacementPoints.standard,
);

void main() {
  late FakeStageRepository stages;

  Future<void> pump(WidgetTester tester, String location, {League league = sampleLeague, List<Override> extra = const []}) async {
    await initializeDateFormatting('pt_BR');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.reset);
    final router = GoRouter(initialLocation: location, routes: [
      GoRoute(path: '/ranking', builder: (_, _) => const RankingScreen()),
      GoRoute(path: '/stages/new', builder: (_, _) => const StageAttendanceScreen()),
      GoRoute(path: '/stages/:id', builder: (_, state) => StageScreen(stageId: state.pathParameters['id']!)),
    ]);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...deviceOverrides(FakeAuthRepository(session: const AuthSession(uid: 'u1')), MemoryLocalStore(),
            leagues: [league]),
        stageRepositoryProvider.overrideWithValue(stages),
        meProvider.overrideWith((ref) async => anaMe),
        ...extra,
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

  setUp(() => stages = FakeStageRepository(Stage.fromJson(stageJson())));

  test('a stage names its pairs, guests included', () {
    final stage = Stage.fromJson(stageJson());
    expect(stage.pairNames(1), 'Ana e Beto');
    expect(stage.pairNames(4), 'Gil e Hugo (convidado)');
    expect(stage.started, isTrue);
    expect(groupName(2), 'Grupo B');
  });

  testWidgets('shows the group table and games; a member enters a score', (tester) async {
    await pump(tester, '/stages/st1');

    expect(find.text('Rodada 1'), findsOneWidget);
    expect(find.text('Rodada 2'), findsOneWidget);
    expect(find.text('Classificação'), findsOneWidget);
    expect(find.text('Grupos'), findsOneWidget, reason: 'the phase being played');
    expect(find.text('Mata-mata'), findsOneWidget, reason: 'what comes next');
    expect(find.descendant(of: find.byKey(const Key('fixture-1')), matching: find.text('3')), findsOneWidget);
    expect(find.text('Lançar placar'), findsNWidgets(2), reason: 'games 2 and 3 have no score');
    expect(find.byTooltip('Ações do placar'), findsNothing, reason: 'members do not correct scores');

    await tester.tap(find.text('Lançar placar').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stage-score-a')), '6');
    await tester.enterText(find.byKey(const Key('stage-score-b')), '5');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Placar inválido para o formato tradicional.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('stage-score-b')), '4');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(stages.calls, ['score:2:6-4:-']);
    expect(find.text('Placar lançado.'), findsOneWidget);
  });

  testWidgets('who may not enter scores sees no button', (tester) async {
    stages = FakeStageRepository(Stage.fromJson(stageJson(canEnterScores: false)));
    await pump(tester, '/stages/st1');

    expect(find.text('Lançar placar'), findsNothing);
  });

  testWidgets('a closed group phase offers the administrator to reopen it', (tester) async {
    stages = FakeStageRepository(Stage.fromJson(stageJson(canAdminister: true, knockoutDrawn: true)))
      ..errors.add(const ApiException('A fase de grupos está fechada.', code: 'STAGE_GROUPS_CLOSED', statusCode: 409));
    await pump(tester, '/stages/st1', league: adminLeague);

    await tester.tap(find.byTooltip('Ações do placar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corrigir placar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stage-score-b')), '2');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(stages.calls, ['score:1:6-2:2'], reason: 'a correction sends the version it saw');
    expect(find.text('A fase de grupos está fechada.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reabrir grupos'));
    await tester.pumpAndSettle();
    expect(stages.calls.last, 'reopen');
  });

  testWidgets('a finished stage shows its podium', (tester) async {
    stages = FakeStageRepository(Stage.fromJson(stageJson(finished: true)));
    await pump(tester, '/stages/st1');

    expect(find.text('Campeões'), findsOneWidget);
    expect(find.text('3º lugar'), findsWidgets, reason: 'the podium and the phase');
    expect(find.text('4º lugar'), findsOneWidget);
    expect(find.byKey(const Key('phase-THIRD_PLACE')), findsOneWidget);
    expect(find.byKey(const Key('phase-FINAL')), findsOneWidget);
    expect(find.text('Mata-mata'), findsNothing);

    await tester.tap(find.byKey(const Key('phase-THIRD_PLACE')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fixture-7')), findsOneWidget);
    expect(find.byKey(const Key('fixture-1')), findsNothing, reason: 'only the games of that phase');
  });

  testWidgets('presence: 8 to 32 players, an even number, then the draw', (tester) async {
    final members = [
      for (final (i, name) in _names.take(7).indexed)
        LeagueMember(
          playerId: 'p-${name.toLowerCase()}',
          displayName: name,
          role: i == 0 ? LeagueRole.admin : LeagueRole.member,
          joinedAt: DateTime(2026),
        ),
    ];
    await pump(tester, '/stages/new', league: adminLeague, extra: [
      leagueMembersProvider.overrideWith((ref, id) async => members),
    ]);

    for (final name in _names.take(7)) {
      await tester.tap(find.text(name));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sortear duplas'));
    await tester.pumpAndSettle();
    expect(find.text('Marque pelo menos 8 jogadores.'), findsOneWidget);

    Future<void> addGuest(String name) async {
      await tester.enterText(find.byKey(const Key('guest-name')), name);
      await tester.tap(find.byTooltip('Adicionar convidado'));
      await tester.pumpAndSettle();
    }

    await addGuest('  Hugo  ');
    await addGuest('Ivo');
    await tester.tap(find.text('Sortear duplas'));
    await tester.pumpAndSettle();
    expect(find.text('Número ímpar de jogadores'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(stages.calls, isEmpty);

    await tester.tap(find.byTooltip('Remover Ivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sortear duplas'));
    await tester.pumpAndSettle();

    expect(stages.calls, ['create:STANDARD:8']);
    expect(stages.created!.last.guestName, 'Hugo');
    expect(find.text('Grupo A'), findsWidgets, reason: 'opens the drawn stage');
  });

  testWidgets('on a playing day without a stage the administrator is asked; "Hoje não" hides it', (tester) async {
    stages = FakeStageRepository(Stage.fromJson(stageJson()));
    await pump(tester, '/ranking', league: adminLeague, extra: [
      currentRankingProvider.overrideWith((ref) async => Cached(SeasonRanking(season: _tournament, entries: const []))),
      todayProvider.overrideWithValue(DateTime(2026, 11, 7)),
      stagesProvider.overrideWith((ref) async => const []),
    ]);

    expect(find.text('Hoje é dia de jogo. Vai ter etapa?'), findsOneWidget);
    await tester.tap(find.text('Hoje não'));
    await tester.pumpAndSettle();
    expect(find.text('Hoje é dia de jogo. Vai ter etapa?'), findsNothing);
  });

  testWidgets('today\'s stage shows above the ranking', (tester) async {
    await pump(tester, '/ranking', extra: [
      currentRankingProvider.overrideWith((ref) async => Cached(SeasonRanking(season: _tournament, entries: const []))),
      todayProvider.overrideWithValue(DateTime(2026, 11, 6)),
    ]);

    expect(find.text('Etapa de hoje'), findsOneWidget);
    expect(find.text('Rodada 1'), findsOneWidget, reason: 'the stage shows first');

    await tester.tap(find.text('Ranking'));
    await tester.pumpAndSettle();
    expect(find.text('Rodada 1'), findsNothing);
  });
}
