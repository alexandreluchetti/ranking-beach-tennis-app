import 'package:flutter/material.dart';

import '../../core/widgets/async_states.dart';

/// Placeholder for areas built in the next stages.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyMessage(icon: icon, title: 'Em construção', message: 'Esta área chega nas próximas versões.'),
      );
}
