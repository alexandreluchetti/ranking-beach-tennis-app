import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_mode_controller.dart';
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
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        children: [
          if (me != null)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(me.displayName),
              subtitle: Text(me.email ?? ''),
              trailing: const Icon(Icons.edit),
              onTap: () => _editName(context, me.displayName),
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
    );
  }

  Future<void> _editName(BuildContext context, String current) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => DisplayNameDialog(current: current),
    );
    if (saved ?? false) {
      messenger.showSnackBar(const SnackBar(content: Text('Nome atualizado.')));
    }
  }
}
