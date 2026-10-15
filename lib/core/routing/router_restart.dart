import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a new router starts. Bumping [epoch] recreates the router, which
/// drops the navigation history of every tab (e.g. a match of the previous
/// league left open in another tab).
class RouterStart {
  const RouterStart(this.location, [this.epoch = 0]);

  final String location;
  final int epoch;
}

class RouterRestartController extends Notifier<RouterStart> {
  @override
  RouterStart build() => const RouterStart('/ranking');

  void restartAt(String location) => state = RouterStart(location, state.epoch + 1);
}

final routerRestartProvider = NotifierProvider<RouterRestartController, RouterStart>(RouterRestartController.new);
