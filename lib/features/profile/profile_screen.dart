import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_mode_controller.dart';
import '../auth/auth_providers.dart';
import '../auth/sign_out.dart';
import '../me/me_repository.dart';
import 'display_name_dialog.dart';

/// "Perfil": the signed-in player's name, leagues, theme and sign-out. League
/// administration lives on each league's page.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final me = ref.watch(meProvider).value;
    final statistics = ref.watch(myStatisticsProvider);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([ref.refresh(meProvider.future), ref.refresh(myStatisticsProvider.future)]),
        child: ListView(
          // Pull to refresh works even when everything fits on the screen.
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // One block: display name, full name and e-mail, with a single edit button.
            if (me != null)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(me.displayName),
                subtitle: Text([me.fullName ?? 'Nome completo não informado', ?me.email].join('\n')),
                isThreeLine: me.email != null,
                trailing: IconButton(
                  tooltip: 'Editar nomes',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editNames(context, me),
                ),
              ),
            // Only accounts with e-mail and password have one to change.
            if (ref.watch(sessionProvider).value?.hasPassword ?? false)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Alterar senha'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/password'),
              ),
            const Divider(),
            section('Tema'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Escuro'), icon: Icon(Icons.dark_mode)),
                ],
                selected: {themeMode},
                onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).select(s.single),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _GlobalStatsCard(
                statistics: statistics,
                onRetry: () => ref.invalidate(myStatisticsProvider),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Minhas ligas'),
              subtitle: const Text('Criar, explorar, convites e administração'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/leagues'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Sobre o app'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/about'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sair'),
              onTap: () => ref.read(signOutProvider)(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNames(BuildContext context, Me me) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => NamesDialog(me: me),
    );
    if (saved ?? false) {
      messenger.showSnackBar(const SnackBar(content: Text('Nome atualizado.')));
    }
  }
}

/// "Minhas estatísticas": the user's matches over every league, without
/// points (each league has its own ranking).
class _GlobalStatsCard extends StatelessWidget {
  const _GlobalStatsCard({required this.statistics, required this.onRetry});

  final AsyncValue<GlobalStats> statistics;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget number(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: theme.textTheme.titleLarge),
              Text(label, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Minhas estatísticas', style: theme.textTheme.labelLarge),
            Text('Todas as ligas somadas, sem pontos', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            // While reloading, the previous numbers stay on screen.
            switch (statistics) {
              AsyncValue(:final value?) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    number('${value.matchesPlayed}', 'partidas'),
                    number('${value.wins}', 'vitórias'),
                    number('${value.losses}', 'derrotas'),
                    number(value.gameDifference > 0 ? '+${value.gameDifference}' : '${value.gameDifference}',
                        'saldo de games'),
                    number(value.winRate == null ? '—' : '${value.winRate}%', 'aproveitamento'),
                  ],
                ),
              AsyncError() => Row(
                  children: [
                    Expanded(child: Text('Não foi possível carregar.', style: theme.textTheme.bodyMedium)),
                    TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
                  ],
                ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ],
        ),
      ),
    );
  }
}
