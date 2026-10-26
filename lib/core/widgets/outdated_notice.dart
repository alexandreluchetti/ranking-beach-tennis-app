import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../storage/read_cache.dart';

/// Discreet line shown while the screens display data saved on the device
/// because the server could not be reached: "Sem conexão — exibindo dados de
/// 14:32" (with the date when it is not from today).
class OutdatedNotice extends ConsumerWidget {
  const OutdatedNotice({super.key, this.now = DateTime.now});

  final DateTime Function() now;

  static final _time = DateFormat('HH:mm', 'pt_BR');
  static final _dateTime = DateFormat("dd/MM 'às' HH:mm", 'pt_BR');

  /// The notice text for data saved at [savedAt].
  static String message(OutdatedData data, DateTime today) {
    final saved = data.savedAt;
    final sameDay = saved.year == today.year && saved.month == today.month && saved.day == today.day;
    final when = sameDay ? _time.format(saved) : _dateTime.format(saved);
    return '${data.offline ? 'Sem conexão' : 'Não foi possível atualizar'} — exibindo dados de $when';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(outdatedDataProvider);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: data == null
          ? const SizedBox(width: double.infinity)
          : Material(
              color: scheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message(data, now()),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
