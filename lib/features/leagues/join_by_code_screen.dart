import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/responsive.dart';
import 'current_league.dart';
import 'league_repository.dart';

/// "Entrar com código": joins a league (public or private) with the invite
/// code an administrator shared. [initialCode] comes from an invite link.
class JoinByCodeScreen extends ConsumerStatefulWidget {
  const JoinByCodeScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<JoinByCodeScreen> createState() => _JoinByCodeScreenState();
}

class _JoinByCodeScreenState extends ConsumerState<JoinByCodeScreen> {
  late final _code = TextEditingController(text: widget.initialCode?.toUpperCase());
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Informe o código de convite.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The backend ignores case and spaces.
      final league = await ref.read(leagueRepositoryProvider).joinByCode(_code.text);
      await enterLeague(ref, league.id);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar com código')),
      body: NarrowBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Peça o código de convite a um administrador da liga.'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('invite-code'),
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: InputDecoration(labelText: 'Código de convite', errorText: _error),
              onSubmitted: (_) => _join(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _join,
              child: _busy
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                    )
                  : const Text('Entrar na liga'),
            ),
          ],
        ),
      ),
    );
  }
}
