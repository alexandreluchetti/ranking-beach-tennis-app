import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ranking/scoring_rules_sheet.dart';
import 'app_info.dart';

/// "Sobre o app": versions, a few useful links and the credits.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static const developer = 'Alexandre Lucchetta';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appVersion = ref.watch(appVersionProvider).value;
    final backendVersion = ref.watch(backendVersionProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Sobre o app')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/branding/app_icon.png', width: 88, height: 88),
            ),
          ),
          const SizedBox(height: 12),
          Text('Ranking Beach Tennis', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            'Ranking individual de beach tennis do grupo',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Versão do app'),
            trailing: Text(appVersion ?? '…'),
          ),
          if (backendVersion != null)
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Versão do servidor'),
              trailing: Text(backendVersion),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Regras de pontuação'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showScoringRules(context),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Licenças de código aberto'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Ranking Beach Tennis',
              applicationVersion: appVersion,
            ),
          ),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Desenvolvido por $developer',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
