import 'package:flutter/material.dart';

import 'ranking_models.dart';

/// Opens the scoring rules as a draggable sheet over the current screen.
Future<void> showScoringRules(BuildContext context, {Season? season}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scroll) => ScoringRules(controller: scroll, season: season),
      ),
    );

/// How the ranking works, in the players' words. Only the approved rules
/// (backend docs/decisions.md D-002 to D-006, D-013, D-014, D-026 to D-030);
/// the points themselves are always calculated by the backend. Both season
/// formats are explained; opened from a daily tournament season, its stages
/// (with that season's placement points) come first.
class ScoringRules extends StatelessWidget {
  const ScoringRules({super.key, this.controller, this.season});

  final ScrollController? controller;
  final Season? season;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tournamentFirst = season?.isDailyTournament ?? false;
    Widget title(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(text, style: theme.textTheme.titleMedium),
        );
    Widget paragraph(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(text, style: theme.textTheme.bodyMedium),
        );
    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  '),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );

    // The daily tournament (D-026 to D-030): placement points come from
    // [points], the season's own table or the default one.
    List<Widget> tournament(PlacementPoints points, {required bool thisSeason}) => [
          title(thisSeason ? 'Torneio do dia (esta temporada)' : 'Torneio do dia'),
          paragraph('Os pontos vêm das etapas: em cada dia de jogo da temporada pode haver uma etapa, e cada '
              'jogador recebe os pontos da colocação final da sua dupla. Partidas avulsas, fora das etapas, '
              'ficam no histórico e nas estatísticas, mas não valem pontos.'),
          paragraph(thisSeason
              ? 'Pontos por colocação nesta temporada:'
              : 'Pontos por colocação (tabela padrão; cada temporada pode ter a sua, definida antes de começar):'),
          for (final (label, value) in _placements(points)) bullet('$label: $value pontos'),
          paragraph('O ranking da temporada soma os pontos de todas as etapas. Desempate: mais pontos, mais '
              'títulos, mais finais (campeão ou vice; o 3º lugar não conta como final) e melhor saldo de games.'),
          title('Como é uma etapa'),
          bullet('O administrador marca quem está presente: membros da liga e convidados, de 8 a 64 jogadores, '
              'em número par.'),
          bullet('O app sorteia duplas fixas para o dia inteiro e as divide em grupos. O sorteio pode ser refeito '
              'até o primeiro placar.'),
          bullet('O administrador escolhe o formato dos jogos da etapa: tradicional (até 6 games) ou curto '
              '(até 4).'),
          bullet('Nos grupos, todas as duplas jogam entre si, em rodadas. Na classificação do grupo vale, nesta '
              'ordem: vitórias, saldo de games, games vencidos e a ordem do sorteio. As duas primeiras de cada grupo passam.'),
          title('Mata-mata'),
          paragraph('O mata-mata é sorteado quando todos os jogos dos grupos têm placar, e depende do número de '
              'duplas:'),
          bullet('4 ou 5 duplas: um grupo; as duas primeiras fazem a final.'),
          bullet('6 a 8 duplas: dois grupos; semifinais, disputa de 3º lugar e final.'),
          bullet('9 a 12 duplas: três grupos; quartas de final (os dois melhores primeiros colocados vão direto '
              'à semifinal), semifinais, 3º lugar e final.'),
          bullet('13 a 16 duplas: quatro grupos; quartas, semifinais, 3º lugar e final.'),
          bullet('17 a 32 duplas: de cinco a oito grupos; o mata-mata começa nas oitavas (com menos de 16 '
              'classificados, os melhores vão direto às quartas).'),
          bullet('Com semifinal, os perdedores disputam o 3º lugar, sorteado junto com a final. A etapa termina '
              'quando a final e o 3º lugar têm placar.'),
          title('Convidados e placares da etapa'),
          bullet('Convidados jogam e ocupam lugar, mas não recebem pontos nem entram no ranking; o parceiro de um '
              'convidado pontua normalmente.'),
          bullet('Os jogos da etapa contam para as estatísticas de carreira e para "Minhas estatísticas".'),
          bullet('Os placares são lançados na própria etapa. Só os administradores corrigem ou removem um placar; '
              'para mudar um jogo de grupo depois do sorteio do mata-mata, eles reabrem os grupos.'),
        ];

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Text('Regras de pontuação', style: theme.textTheme.headlineSmall),
        paragraph('Cada temporada da liga tem um de dois formatos: pontos por partida ou torneio do dia.'),
        if (tournamentFirst) ...tournament(season!.placementPoints ?? PlacementPoints.standard, thisSeason: true),
        title(tournamentFirst ? 'Pontos por partida (outras temporadas)' : 'Pontos por partida'),
        paragraph('Cada jogador recebe os games feitos pela sua dupla. '
            'Os vencedores ganham mais 3 pontos de bônus.'),
        const SizedBox(height: 8),
        const _ExamplesTable(),
        title('Placares válidos'),
        bullet('Tradicional (até 6 games): 6–0, 6–1, 6–2, 6–3, 6–4, 7–5 ou 7–6 (tie-break).'),
        bullet('Curto (até 4 games): 4–0, 4–1, 4–2, 5–3 ou 5–4 (tie-break).'),
        bullet('O tie-break conta como um game para quem venceu: 6–6 vira 7–6 e 4–4 vira 5–4.'),
        bullet('Os pontos do tie-break são opcionais e ficam só no histórico; não mudam a pontuação.'),
        title('Partidas com convidado'),
        paragraph('Partidas com convidado (pessoa sem conta no app) contam normalmente; o convidado não '
            'recebe pontos.'),
        title('Desempate no ranking'),
        paragraph('Cada jogador tem uma posição própria (1º, 2º, 3º…). Em caso de empate, vale, nesta ordem:'),
        bullet('1º  Mais pontos.'),
        bullet('2º  Mais vitórias.'),
        bullet('3º  Melhor saldo de games.'),
        bullet('4º  Menos partidas jogadas (o mesmo resultado em menos jogos fica na frente).'),
        bullet('5º  Mais games vencidos.'),
        bullet('6º  Quem chegou primeiro à pontuação atual.'),
        bullet('7º  Quem entrou primeiro na liga; depois, ordem alfabética do nome; por fim, '
            'quem se cadastrou primeiro no app.'),
        title('Temporadas'),
        bullet('Só contam para o ranking as partidas jogadas dentro do período da temporada '
            '(início e término incluídos).'),
        bullet('Partidas fora de uma temporada ficam no histórico, sem pontos, e contam só para as '
            'estatísticas de carreira.'),
        bullet('Uma partida registrada depois, mas jogada dentro de uma temporada já encerrada, '
            'ainda conta para ela.'),
        title('Quem lança os placares'),
        paragraph('Cada liga escolhe se qualquer membro ou só os administradores registram partidas e lançam os '
            'placares das etapas.'),
        title('Correções e anulações'),
        paragraph('Os administradores da liga podem corrigir ou anular partidas. Partidas anuladas não valem pontos '
            'nem estatísticas. O ranking é sempre recalculado a partir das partidas, então os pontos '
            'nunca são contados duas vezes. Os participantes são avisados nas Notificações.'),
        if (!tournamentFirst) ...tournament(PlacementPoints.standard, thisSeason: false),
      ],
    );
  }
}

List<(String, int)> _placements(PlacementPoints p) => [
      ('Campeões', p.champion),
      ('Vice', p.runnerUp),
      ('3º lugar', p.thirdPlace),
      ('4º lugar', p.fourthPlace),
      ('Quartas de final', p.quarterfinal),
      ('Oitavas de final', p.roundOf16),
      ('Fase de grupos', p.groupStage),
    ];

class _ExamplesTable extends StatelessWidget {
  const _ExamplesTable();

  static const _rows = [
    ('6–4', '9', '4'),
    ('7–5', '10', '5'),
    ('7–6 (tie-break)', '10', '6'),
    ('6–0', '9', '0'),
    ('4–2 (curto)', '7', '2'),
    ('5–4 (curto, tie-break)', '8', '4'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = theme.textTheme.labelLarge;
    TableRow row(List<String> cells, {TextStyle? style}) => TableRow(
          children: [
            for (final (i, cell) in cells.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Text(cell, style: style, textAlign: i == 0 ? TextAlign.start : TextAlign.end),
              ),
          ],
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(), 2: FlexColumnWidth()},
        border: TableBorder(horizontalInside: BorderSide(color: theme.colorScheme.outlineVariant)),
        children: [
          row(['Placar', 'Vencedores', 'Perdedores'], style: header),
          for (final (score, winners, losers) in _rows) row([score, winners, losers]),
        ],
      ),
    );
  }
}
