import 'package:flutter/material.dart';

/// Narrowest content column on a wide screen.
const contentMinWidth = 840.0;

/// Share of a wide screen the content column takes, so it grows with the
/// window and keeps margins at the sides.
const contentWidthFactor = 0.85;

/// Width of the content column for the [available] width of a wide screen.
double contentWidth(double available) => (available * contentWidthFactor).clamp(contentMinWidth, available);

/// Widest form column.
const formMaxWidth = 560.0;

/// Whether the screen is large enough for the header navigation and the
/// centered content column: a computer or tablet browser. A phone keeps the
/// mobile layout even lying down, since its height stays small.
bool isWideLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width >= 840 && size.height >= 500;
}

/// Centers [child] in a column that follows the window width on wide screens
/// ([contentWidthFactor] of it, at least [contentMinWidth]); the margins have
/// the same background as the content. On a phone it is just [child].
class ContentFrame extends StatelessWidget {
  const ContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) {
      return child;
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: SizedBox(width: contentWidth(constraints.maxWidth), child: child),
          );
        },
      ),
    );
  }
}

/// Keeps a form at most [formMaxWidth] wide, at the top center of the screen.
class NarrowBody extends StatelessWidget {
  const NarrowBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: formMaxWidth),
          child: child,
        ),
      );
}
