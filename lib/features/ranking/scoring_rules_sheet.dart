import 'package:flutter/material.dart';

/// Opens the scoring rules as a draggable sheet over the current screen.
Future<void> showScoringRules(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scroll) => ScoringRules(controller: scroll),
      ),
    );

/// How the ranking works, in the players' words. Only the approved rules
/// (backend docs/decisions.md D-002 to D-006, D-013, D-014); the points
/// themselves are always calculated by the backend.
class ScoringRules extends StatelessWidget {
  const ScoringRules({super.key, this.controller});

  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Text('Regras de pontuação', style: theme.textTheme.headlineSmall),
        title('Como os pontos são calculados'),
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
        title('Correções e anulações'),
        paragraph('Os administradores da liga podem corrigir ou anular partidas. Partidas anuladas não valem pontos '
            'nem estatísticas. O ranking é sempre recalculado a partir das partidas, então os pontos '
            'nunca são contados duas vezes. Os participantes são avisados nas Notificações.'),
      ],
    );
  }
}

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
