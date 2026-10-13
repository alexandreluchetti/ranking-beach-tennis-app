import 'package:flutter_test/flutter_test.dart';
import 'package:ranking_beach_tennis/features/matches/match_draft.dart';
import 'package:ranking_beach_tennis/features/matches/match_models.dart';

void main() {
  const ana = PlayerSummary(id: 'p-ana', displayName: 'Ana');
  const beto = PlayerSummary(id: 'p-beto', displayName: 'Beto');
  const caio = PlayerSummary(id: 'p-caio', displayName: 'Caio');
  const dani = PlayerSummary(id: 'p-dani', displayName: 'Dani');

  MatchDraft draft({
    MatchFormat format = MatchFormat.standard,
    List<DraftPosition?> positions = const [
      DraftPosition.player(ana),
      DraftPosition.player(beto),
      DraftPosition.player(caio),
      DraftPosition.player(dani),
    ],
    int? a = 6,
    int? b = 4,
    int? tbA,
    int? tbB,
  }) =>
      MatchDraft(
        id: 'id-1',
        playedAt: DateTime.utc(2026, 10, 11, 12),
        format: format,
        positions: positions,
        teamAGames: a,
        teamBGames: b,
        tiebreakTeamAPoints: tbA,
        tiebreakTeamBPoints: tbB,
      );

  test('accepts exactly the approved final scores (D-002)', () {
    const standard = ['6-0', '6-1', '6-2', '6-3', '6-4', '7-5', '7-6'];
    const short = ['4-0', '4-1', '4-2', '5-3', '5-4'];
    for (var a = 0; a <= 8; a++) {
      for (var b = 0; b <= 8; b++) {
        final key = a > b ? '$a-$b' : '$b-$a';
        expect(MatchDraft.isValidScore(MatchFormat.standard, a, b), a != b && standard.contains(key),
            reason: 'standard $a-$b');
        expect(MatchDraft.isValidScore(MatchFormat.short, a, b), a != b && short.contains(key),
            reason: 'short $a-$b');
      }
    }
  });

  test('identifies the winner and the tie-break', () {
    expect(draft(a: 4, b: 6).winner, Team.b);
    expect(draft(a: 7, b: 6).decidedByTiebreak, isTrue);
    expect(draft(format: MatchFormat.short, a: 5, b: 4).decidedByTiebreak, isTrue);
    expect(draft(a: 6, b: 5).winner, isNull);
  });

  test('explains the first problem in Portuguese', () {
    expect(draft(positions: const [DraftPosition.player(ana), null, null, null]).problem,
        'Escolha os quatro participantes.');
    expect(
      draft(positions: const [
        DraftPosition.player(ana),
        DraftPosition.player(beto),
        DraftPosition.player(ana),
        DraftPosition.player(dani),
      ]).problem,
      'A mesma pessoa não pode ocupar duas posições.',
    );
    expect(draft(a: null).problem, 'Informe o placar.');
    expect(draft(a: 6, b: 5).problem, 'Placar inválido para o formato tradicional.');
    expect(draft(a: 7, b: 6, tbA: 7).problem, 'Informe os dois lados do tie-break ou deixe ambos em branco.');
    expect(draft(a: 7, b: 6, tbA: 5, tbB: 7).problem, 'O tie-break deve ser vencido pela dupla vencedora.');
    expect(draft(a: 7, b: 6, tbA: 7, tbB: 5).problem, isNull);
    expect(draft().problem, isNull);
  });

  test('two guests are allowed and never count as the same person', () {
    final withGuests = draft(positions: const [
      DraftPosition.player(ana),
      DraftPosition.guest(),
      DraftPosition.guest('Zé'),
      DraftPosition.player(dani),
    ]);

    expect(withGuests.problem, isNull);
    expect(withGuests.hasGuest, isTrue);
  });

  test('builds the backend payload', () {
    final json = draft(
      positions: const [
        DraftPosition.player(ana),
        DraftPosition.guest('  Zé '),
        DraftPosition.player(caio),
        DraftPosition.guest(),
      ],
      a: 7,
      b: 6,
      tbA: 7,
      tbB: 4,
    ).toJson(confirmPossibleDuplicate: true);

    expect(json['id'], 'id-1');
    expect(json['playedAt'], '2026-10-11T12:00:00.000Z');
    expect(json['format'], 'STANDARD');
    expect(json['teamA'], [
      {'playerId': 'p-ana'},
      {'guest': true, 'guestName': 'Zé'},
    ]);
    expect(json['teamB'], [
      {'playerId': 'p-caio'},
      {'guest': true},
    ]);
    expect(json['tiebreakTeamAPoints'], 7);
    expect(json['confirmPossibleDuplicate'], isTrue);
  });

  test('tie-break points are not sent for scores without a tie-break', () {
    expect(draft(a: 6, b: 4, tbA: 7, tbB: 5).toJson().containsKey('tiebreakTeamAPoints'), isFalse);
  });
}
