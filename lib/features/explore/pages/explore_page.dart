import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/pages/main_page.dart';
import '../../recommend/models/drama.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../providers/explore_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/category_chips_bar.dart';
import '../widgets/explore_drama_grid_card.dart';
import '../widgets/explore_search_bar.dart';
import '../widgets/search_suggestions_panel.dart';

/// ============================================================================
/// 探索页
///
/// 【功能】
/// - 搜索栏（支持搜索建议）
/// - 分类标签栏
/// - 短剧网格展示
/// - 下拉刷新、上拉加载更多
///
/// 【如何修改】
/// - 修改网格列数：_gridColumnCount 方法
/// - 修改搜索逻辑：修改 search_provider.dart
/// - 修改分类逻辑：修改 explore_provider.dart
/// ============================================================================
class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key, this.scrollController});
  final ScrollController? scrollController;

  /// 在切 tab 前调用，清除搜索框焦点
  static void unfocusSearch(BuildContext context) {
    final state = context.findAncestorStateOfType<_ExplorePageState>();
    state?._searchFocusNode.unfocus();
  }

  @override ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  late final ScrollController _scrollController = widget.scrollController ?? ScrollController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.unfocus();
    });
  }

  @override
  void dispose() {
    if (widget.scrollController == null) _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 根据屏幕宽度计算网格列数
  int _gridColumnCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 3;
  }

  /// 滚动监听 - 触发加载更多
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      final metrics = notification.metrics;
      if (metrics.pixels >= metrics.maxScrollExtent - 240) {
        final search = ref.read(searchProvider);
        if (search.hasActiveSearch) ref.read(searchProvider.notifier).loadMoreSearch();
        else ref.read(exploreProvider.notifier).loadMore();
      }
    }
    return false;
  }

  /// 下拉刷新
  Future<void> _onRefresh() async {
    final search = ref.read(searchProvider);
    if (search.hasActiveSearch) await ref.read(searchProvider.notifier).submitSearch(search.debouncedQuery);
    else await ref.read(exploreProvider.notifier).refresh();
  }

  /// 搜索建议点击
  void _onSuggestionTap(String keyword) { _searchFocusNode.unfocus(); ref.read(searchProvider.notifier).submitSearch(keyword); }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final explore = ref.watch(exploreProvider);
    final search = ref.watch(searchProvider);
    final showSearchResults = search.hasActiveSearch;
    final dramas = showSearchResults ? search.searchResults : explore.dramas;
    final isLoading = showSearchResults ? search.isLoadingResults && dramas.isEmpty : explore.isLoading && !explore.hasData;
    final isLoadingMore = showSearchResults ? search.isLoadingResults && dramas.isNotEmpty : explore.isLoadingMore;
    final showSuggestions = search.showSuggestions && _searchFocusNode.hasFocus && !showSearchResults;

    return GradientScaffold(
      body: SafeArea(
        child: GestureDetector(onTap: () => _searchFocusNode.unfocus(), child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: ExploreSearchBar(focusNode: _searchFocusNode, onSubmitted: (_) => _searchFocusNode.unfocus())),
          if (showSuggestions) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SearchSuggestionsPanel(onSuggestionTap: _onSuggestionTap)),
          if (!showSearchResults && explore.categories.isNotEmpty) ...[
            CategoryChipsBar(categories: explore.categories, selectedId: explore.selectedCategoryId, onSelected: ref.read(exploreProvider.notifier).selectCategory),
            const SizedBox(height: 8)],
          Expanded(child: _buildContent(context, l10n, dramas: dramas, isLoading: isLoading, isLoadingMore: isLoadingMore, showSearchResults: showSearchResults, explore: explore, search: search)),
        ])),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppLocalizations l10n, {required List<Drama> dramas, required bool isLoading, required bool isLoadingMore, required bool showSearchResults, required ExploreState explore, required SearchState search}) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (!showSearchResults && explore.hasError && dramas.isEmpty) return _ErrorView(message: explore.errorMessage ?? l10n.unknownError, onRetry: () => ref.read(exploreProvider.notifier).refresh());
    if (showSearchResults && search.errorMessage != null && dramas.isEmpty) return _ErrorView(message: search.errorMessage!, onRetry: () => ref.read(searchProvider.notifier).submitSearch());
    if (dramas.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.search_off, size: 48, color: Theme.of(context).colorScheme.outline), const SizedBox(height: 12),
      Text(showSearchResults ? l10n.noResults : l10n.comingSoon, style: Theme.of(context).textTheme.bodyLarge)]));

    final columnCount = _gridColumnCount(context);
    return RefreshIndicator(onRefresh: _onRefresh, child: NotificationListener<ScrollNotification>(onNotification: _onScrollNotification,
      child: CustomScrollView(controller: _scrollController, physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()), slivers: [
        SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), sliver: SliverGrid(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columnCount, childAspectRatio: 0.52, crossAxisSpacing: 10, mainAxisSpacing: 12),
          delegate: SliverChildBuilderDelegate((context, index) => ExploreDramaGridCard(drama: dramas[index], highlightQuery: showSearchResults ? search.debouncedQuery : null, onTap: () => openDramaPlayer(context, dramas[index])), childCount: dramas.length))),
        if (isLoadingMore) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
      ])));
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message; final VoidCallback onRetry;
  @override Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton(onPressed: onRetry, child: Text(l10n.retry))])));
  }
}
