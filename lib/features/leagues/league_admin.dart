import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import 'current_league.dart';
import 'league_models.dart';
import 'league_repository.dart';

/// Invite links open the web app, which fills in the code (decision: links
/// open the app directly on Android only after 1.1.0).
String inviteLink(String code) => 'https://ranking-beach-tennis.web.app/convite/$code';

/// Opens the system share sheet; overridden in tests.
final shareTextProvider = Provider<Future<void> Function(String text)>(
  (ref) => (text) async => SharePlus.instance.share(ShareParams(text: text)),
);

/// Reloads what an administration change can affect.
void refreshLeague(WidgetRef ref, String leagueId) {
  ref
    ..invalidate(leagueProvider(leagueId))
    ..invalidate(leagueMembersProvider(leagueId))
    ..invalidate(leagueJoinRequestsProvider(leagueId))
    ..invalidate(myLeaguesProvider);
}

/// Runs an administration action, showing [done] or the backend message.
Future<bool> runLeagueAction(BuildContext context, Future<void> Function() action, {String? done}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (done != null) {
      messenger.showSnackBar(SnackBar(content: Text(done)));
    }
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: AppTheme.inlineButton,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// "Administração" on the league page, for those who may administer it
/// (`canAdminister`) while it is not archived.
class LeagueAdminSection extends ConsumerWidget {
  const LeagueAdminSection({super.key, required this.league});

  final League league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(leagueJoinRequestsProvider(league.id)).value ?? const <JoinRequest>[];
    final isCurrent = ref.watch(currentLeagueIdProvider) == league.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Administração', style: Theme.of(context).textTheme.titleSmall),
        ),
        ListTile(
          leading: const Icon(Icons.person_add_alt),
          title: const Text('Convidar'),
          subtitle: const Text('Por e-mail ou com o código de convite'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/leagues/${league.id}/invite'),
        ),
        ListTile(
          leading: Badge(
            isLabelVisible: requests.isNotEmpty,
            label: Text('${requests.length}'),
            child: const Icon(Icons.how_to_reg_outlined),
          ),
          title: const Text('Pedidos para entrar'),
          subtitle: Text(requests.isEmpty ? 'Nenhum pedido pendente' : '${requests.length} pendente(s)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/leagues/${league.id}/requests'),
        ),
        ListTile(
          leading: const Icon(Icons.event_note),
          title: const Text('Temporadas'),
          subtitle: Text(isCurrent ? 'Criar, alterar e encerrar temporadas' : 'Abra esta liga para gerenciar'),
          trailing: const Icon(Icons.chevron_right),
          enabled: isCurrent,
          onTap: () => context.push('/leagues/${league.id}/seasons'),
        ),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Editar liga'),
          subtitle: const Text('Nome, descrição e visibilidade'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/leagues/${league.id}/edit'),
        ),
        ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text('Arquivar liga'),
          onTap: () => _archive(context, ref),
        ),
      ],
    );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Arquivar liga?',
      message: 'A liga fica somente leitura: ninguém entra, e não é possível registrar partidas, '
          'criar temporadas nem mudar membros. O ranking e o histórico continuam visíveis para os membros. '
          'Só o administrador geral pode desarquivar.',
      action: 'Arquivar',
    );
    if (!ok || !context.mounted) {
      return;
    }
    await runLeagueAction(context, () async {
      await ref.read(leagueRepositoryProvider).archive(league.id);
      refreshLeague(ref, league.id);
    }, done: 'Liga arquivada.');
  }
}

enum _MemberAction { promote, revoke, remove }

/// Promote, revoke or remove a member (league administrators only).
class MemberAdminMenu extends ConsumerWidget {
  const MemberAdminMenu({super.key, required this.league, required this.member, required this.isMe});

  final League league;
  final LeagueMember member;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<_MemberAction>(
        tooltip: 'Ações para ${member.displayName}',
        onSelected: (action) => _run(context, ref, action),
        itemBuilder: (_) => [
          if (member.role == LeagueRole.member)
            const PopupMenuItem(
              value: _MemberAction.promote,
              child: ListTile(leading: Icon(Icons.shield_outlined), title: Text('Promover a admin')),
            )
          else
            PopupMenuItem(
              value: _MemberAction.revoke,
              child: ListTile(
                leading: const Icon(Icons.remove_moderator_outlined),
                title: Text(isMe ? 'Deixar de ser admin' : 'Revogar admin'),
              ),
            ),
          if (!isMe)
            const PopupMenuItem(
              value: _MemberAction.remove,
              child: ListTile(leading: Icon(Icons.person_remove_outlined), title: Text('Remover da liga')),
            ),
        ],
      );

  Future<void> _run(BuildContext context, WidgetRef ref, _MemberAction action) async {
    final name = member.displayName;
    final (title, message, label, done) = switch (action) {
      _MemberAction.promote => (
          'Promover $name?',
          '$name poderá administrar a liga: temporadas, partidas, membros e convites.',
          'Promover',
          '$name agora é admin.',
        ),
      _MemberAction.revoke => isMe
          ? (
              'Deixar de ser admin?',
              'Você continua membro, mas não poderá mais administrar a liga.',
              'Confirmar',
              'Você não é mais admin desta liga.',
            )
          : ('Revogar admin de $name?', '$name continua membro da liga.', 'Revogar', '$name não é mais admin.'),
      _MemberAction.remove => (
          'Remover $name?',
          'As partidas de $name continuam valendo. Para voltar, será preciso entrar de novo.',
          'Remover',
          '$name foi removido da liga.',
        ),
    };
    if (!await confirm(context, title: title, message: message, action: label) || !context.mounted) {
      return;
    }
    final repository = ref.read(leagueRepositoryProvider);
    await runLeagueAction(context, () async {
      switch (action) {
        case _MemberAction.promote:
          await repository.changeRole(league.id, member.playerId, LeagueRole.admin);
        case _MemberAction.revoke:
          await repository.changeRole(league.id, member.playerId, LeagueRole.member);
        case _MemberAction.remove:
          await repository.removeMember(league.id, member.playerId);
      }
      refreshLeague(ref, league.id);
    }, done: done);
  }
}

/// "Pedidos para entrar": accept or reject each pending request.
class JoinRequestsScreen extends ConsumerWidget {
  const JoinRequestsScreen({super.key, required this.leagueId});

  final String leagueId;

  static final _date = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(leagueJoinRequestsProvider(leagueId));
    final league = ref.watch(leagueProvider(leagueId)).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos para entrar')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(leagueJoinRequestsProvider(leagueId).future),
        child: requests.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              ErrorRetry(error: error, onRetry: () => ref.invalidate(leagueJoinRequestsProvider(leagueId))),
          data: (requests) => ListView(
            children: [
              if (league != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('${league.name} · ${league.membersLabel} membros'),
                ),
              if (requests.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: EmptyMessage(icon: Icons.how_to_reg_outlined, title: 'Nenhum pedido pendente'),
                ),
              for (final request in requests)
                ListTile(
                  title: Text(request.displayName),
                  subtitle: Text('Pedido em ${_date.format(request.createdAt)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Recusar ${request.displayName}',
                        icon: const Icon(Icons.close),
                        onPressed: () => _answer(context, ref, request, accept: false),
                      ),
                      IconButton.filled(
                        tooltip: 'Aceitar ${request.displayName}',
                        icon: const Icon(Icons.check),
                        onPressed: () => _answer(context, ref, request, accept: true),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _answer(BuildContext context, WidgetRef ref, JoinRequest request, {required bool accept}) async {
    final repository = ref.read(leagueRepositoryProvider);
    await runLeagueAction(context, () async {
      try {
        if (accept) {
          await repository.acceptJoinRequest(leagueId, request.id);
        } else {
          await repository.rejectJoinRequest(leagueId, request.id);
        }
      } finally {
        // Also when it was already answered by another administrator.
        refreshLeague(ref, leagueId);
      }
    }, done: accept ? '${request.displayName} entrou na liga.' : 'Pedido de ${request.displayName} recusado.');
  }
}

/// "Convidar": an in-app invitation by e-mail, or the invite code and link.
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key, required this.leagueId});

  final String leagueId;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _email = TextEditingController();
  bool _sending = false;
  String? _emailError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _emailError = 'Informe um e-mail válido.');
      return;
    }
    setState(() {
      _sending = true;
      _emailError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(leagueRepositoryProvider).invite(widget.leagueId, email);
      _email.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Convite enviado.')));
    } on ApiException catch (e) {
      setState(() => _emailError = e.message);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _generate(String? current) async {
    if (current != null &&
        !await confirm(
          context,
          title: 'Gerar novo código?',
          message: 'O código atual ($current) e o link dele deixam de funcionar.',
          action: 'Gerar',
        )) {
      return;
    }
    if (!mounted) {
      return;
    }
    await runLeagueAction(context, () async {
      await ref.read(leagueRepositoryProvider).regenerateInviteCode(widget.leagueId);
      ref.invalidate(leagueInviteCodeProvider(widget.leagueId));
    }, done: 'Novo código gerado.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = ref.watch(leagueInviteCodeProvider(widget.leagueId));
    final league = ref.watch(leagueProvider(widget.leagueId)).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Convidar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Convite por e-mail', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Digite o e-mail exato da conta da pessoa no app. Ela recebe o convite nas notificações e decide se entra.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('invite-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(labelText: 'E-mail', errorText: _emailError),
            onSubmitted: (_) => _invite(),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _sending ? null : _invite, child: const Text('Enviar convite')),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text('Código de convite', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Quem tiver o código ou o link entra direto, mesmo numa liga privada.'),
          const SizedBox(height: 16),
          ...code.when(
            loading: () => const [Center(child: CircularProgressIndicator())],
            error: (error, _) => [
              SizedBox(
                height: 200,
                child: ErrorRetry(
                  error: error,
                  onRetry: () => ref.invalidate(leagueInviteCodeProvider(widget.leagueId)),
                ),
              ),
            ],
            data: (code) => code == null
                ? [
                    const Text('Nenhum código gerado ainda.'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => _generate(null), child: const Text('Gerar código')),
                  ]
                : [
                    Center(
                      child: SelectableText(
                        code,
                        style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 4, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(child: Text(inviteLink(code), style: theme.textTheme.bodySmall)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await Clipboard.setData(ClipboardData(text: inviteLink(code)));
                              messenger.showSnackBar(const SnackBar(content: Text('Link copiado.')));
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copiar link'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => ref.read(shareTextProvider)(
                              'Entre na liga ${league?.name ?? ''} no Ranking Beach Tennis: ${inviteLink(code)} '
                              '(código $code)',
                            ),
                            icon: const Icon(Icons.share),
                            label: const Text('Compartilhar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: () => _generate(code), child: const Text('Gerar novo código')),
                  ],
          ),
        ],
      ),
    );
  }
}
