import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/async_states.dart';
import '../../core/widgets/list_detail.dart';
import 'match_card.dart';
import 'match_models.dart';
import 'match_repository.dart';

class MatchHistoryState {
  const MatchHistoryState({required this.items, required this.hasNext, this.loadingMore = false});

  final List<MatchView> items;
  final bool hasNext;
  final bool loadingMore;
}

/// Most recent matches first, loaded page by page for one filter.
class MatchHistory extends AsyncNotifier<MatchHistoryState> {
  MatchHistory(this.filter);

  final MatchFilter filter;
  int _page = 0;

  @override
  Future<MatchHistoryState> build() async {
    _page = 0;
    final page = await ref.watch(matchRepositoryProvider).search(filter);
    return MatchHistoryState(items: page.items, hasNext: page.hasNext);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasNext || current.loadingMore) {
      return;
    }
    state = AsyncData(MatchHistoryState(items: current.items, hasNext: true, loadingMore: true));
    try {
      final next = await ref.read(matchRepositoryProvider).search(filter, page: _page + 1);
      _page++;
      state = AsyncData(MatchHistoryState(items: [...current.items, ...next.items], hasNext: next.hasNext));
    } catch (_) {
      // Keep what was loaded; the user can scroll again to retry.
      state = AsyncData(MatchHistoryState(items: current.items, hasNext: true));
    }
  }
}

final matchHistoryProvider =
    AsyncNotifierProvider.family<MatchHistory, MatchHistoryState, MatchFilter>(MatchHistory.new);

/// The history as slivers, so it can sit below other content (filters, profile).
class MatchHistorySliver extends ConsumerWidget {
  const MatchHistorySliver({super.key, required this.filter, this.emptyMessage = 'Nenhuma partida encontrada.'});

  final MatchFilter filter;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(matchHistoryProvider(filter));
    return history.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      ),
      error: (error, _) => SliverToBoxAdapter(
        child: ErrorRetry(error: error, onRetry: () => ref.invalidate(matchHistoryProvider(filter))),
      ),
      data: (state) {
        if (state.items.isEmpty) {
          return SliverToBoxAdapter(
            child: EmptyMessage(icon: Icons.sports_tennis, title: emptyMessage),
          );
        }
        return SliverList.builder(
          itemCount: state.items.length + (state.hasNext ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == state.items.length) {
              // Reached the end of what is loaded: fetch the next page after this frame.
              Future.microtask(() => ref.read(matchHistoryProvider(filter).notifier).loadMore());
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final match = state.items[i];
            final path = '/matches/${match.id}';
            return MatchCard(
              match: match,
              selected: isOpenInDetail(context, path),
              onTap: () => openDetail(context, path),
            );
          },
        );
      },
    );
  }
}
