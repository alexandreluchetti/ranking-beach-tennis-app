import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'responsive.dart';

/// On a wide screen, a list with the opened item beside it, without leaving the
/// list; on a phone, just the list (items open on their own screen).
///
/// Items open through [openDetail] with their usual address: inside a
/// [ListDetail] whose [pathPrefix] matches, the item shows beside the list;
/// anywhere else the address is pushed as before.
class ListDetail extends StatefulWidget {
  const ListDetail({
    super.key,
    required this.pathPrefix,
    required this.list,
    required this.detailBuilder,
    required this.placeholder,
  });

  /// Address of an item without its id, such as `/matches/`.
  final String pathPrefix;
  final Widget list;
  final Widget Function(String id) detailBuilder;

  /// Shown beside the list while nothing is open.
  final Widget placeholder;

  @override
  State<ListDetail> createState() => _ListDetailState();
}

class _ListDetailState extends State<ListDetail> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) {
      return widget.list;
    }
    final selected = _selectedId;
    return _ListDetailScope(
      pathPrefix: widget.pathPrefix,
      selectedId: selected,
      open: (id) => setState(() => _selectedId = id),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: widget.list),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 3,
            child: selected == null
                ? widget.placeholder
                : KeyedSubtree(key: ValueKey(selected), child: widget.detailBuilder(selected)),
          ),
        ],
      ),
    );
  }
}

class _ListDetailScope extends InheritedWidget {
  const _ListDetailScope({
    required this.pathPrefix,
    required this.selectedId,
    required this.open,
    required super.child,
  });

  final String pathPrefix;
  final String? selectedId;
  final ValueChanged<String> open;

  static _ListDetailScope? _for(BuildContext context, String path, {required bool listen}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<_ListDetailScope>()
        : context.getInheritedWidgetOfExactType<_ListDetailScope>();
    return scope != null && path.startsWith(scope.pathPrefix) ? scope : null;
  }

  @override
  bool updateShouldNotify(_ListDetailScope oldWidget) =>
      selectedId != oldWidget.selectedId || pathPrefix != oldWidget.pathPrefix;
}

/// Opens [path] beside the list when there is room for it, else on its own screen.
void openDetail(BuildContext context, String path) {
  final scope = _ListDetailScope._for(context, path, listen: false);
  if (scope == null) {
    context.push(path);
  } else {
    scope.open(path.substring(scope.pathPrefix.length));
  }
}

/// Whether [path] is the item open beside the list, to highlight it.
bool isOpenInDetail(BuildContext context, String path) {
  final scope = _ListDetailScope._for(context, path, listen: true);
  return scope != null && path == '${scope.pathPrefix}${scope.selectedId}';
}
