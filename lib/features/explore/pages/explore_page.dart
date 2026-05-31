import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/pages/main_page.dart';
import '../../recommend/models/drama.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../models/category.dart';
import '../providers/explore_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/explore_drama_grid_card.dart';
import '../widgets/explore_search_bar.dart';
import '../widgets/search_suggestions_panel.dart';

class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key, this.scrollController});
  final ScrollController? scrollController;

  static void unfocusSearch(BuildContext context) {
    final state = context.findAncestorStateOfType<_ExplorePageState>();
    state?._searchFocusNode.unfocus();
  }

  @override ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  late final ScrollController _scrollController = widget.scrollController ?? ScrollController();
  final _searchFocusNode = FocusNode();
  final _moreButtonKey = GlobalKey();
  final _rightPanelKey = GlobalKey();
  final _filterBarKey = GlobalKey();
  OverlayEntry? _dropdownOverlay;

  @override
  void dispose() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
    if (widget.scrollController == null) _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.unfocus();
    });
  }

  int _gridColumnCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 3;
  }

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

  Future<void> _onRefresh() async {
    final search = ref.read(searchProvider);
    if (search.hasActiveSearch) await ref.read(searchProvider.notifier).submitSearch(search.debouncedQuery);
    else await ref.read(exploreProvider.notifier).refresh();
  }

  void _onSuggestionTap(String keyword) { _searchFocusNode.unfocus(); ref.read(searchProvider.notifier).submitSearch(keyword); }

  void _showMoreCategoriesMenu(BuildContext context, List<Category> categories, String selectedId) {
    if (_dropdownOverlay != null) {
      _dropdownOverlay?.remove();
      _dropdownOverlay = null;
      return;
    }

    final RenderBox moreButtonBox = _moreButtonKey.currentContext!.findRenderObject() as RenderBox;
    final Offset moreButtonOffset = moreButtonBox.localToGlobal(Offset.zero);
    final double arrowCenterX = moreButtonOffset.dx + moreButtonBox.size.width / 2;

    final RenderBox filterBarBox = _filterBarKey.currentContext!.findRenderObject() as RenderBox;
    final Offset filterBarOffset = filterBarBox.localToGlobal(Offset.zero);
    final double filterBarWidth = filterBarBox.size.width;
    final double dropdownWidth = filterBarWidth - 32;
    final double dropdownLeft = filterBarOffset.dx + 16;
    final double dropdownTop = moreButtonOffset.dy + moreButtonBox.size.height;

    _dropdownOverlay = OverlayEntry(
      builder: (ctx) => _CategoriesDropdown(
        categories: categories,
        selectedId: selectedId,
        left: dropdownLeft,
        top: dropdownTop,
        arrowCenterX: arrowCenterX,
        barWidth: dropdownWidth,
        onClose: () {
          _dropdownOverlay?.remove();
          _dropdownOverlay = null;
        },
        onSelect: (id) {
          ref.read(exploreProvider.notifier).selectCategory(id);
          _dropdownOverlay?.remove();
          _dropdownOverlay = null;
        },
      ),
    );

    Overlay.of(context).insert(_dropdownOverlay!);
  }

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
        child: GestureDetector(
          onTap: () => _searchFocusNode.unfocus(),
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: ExploreSearchBar(focusNode: _searchFocusNode, onSubmitted: (_) => _searchFocusNode.unfocus())),
            if (showSuggestions) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SearchSuggestionsPanel(onSuggestionTap: _onSuggestionTap)),
            if (!showSearchResults && explore.categories.isNotEmpty) ...[
              _buildFilterBar(context, l10n, explore),
              const SizedBox(height: 8),
            ],
            Expanded(child: _buildContent(context, l10n, dramas: dramas, isLoading: isLoading, isLoadingMore: isLoadingMore, showSearchResults: showSearchResults, explore: explore, search: search)),
          ]),
        ),
      ),
    );
  }

  /// 筛选栏：左边64%滚动分类chips，右边36%固定Hot/New/更多
  Widget _buildFilterBar(BuildContext context, AppLocalizations l10n, ExploreState explore) {
    final locale = Localizations.localeOf(context);

    return SizedBox(
      key: _filterBarKey,
      // height: 24,
      child: Row(
        children: [
          // 左边64%：可滚动的分类chips
          Expanded(
            flex: 64,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 16),
              child: ClipRect(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 24),
                    child: Row(
                      children: [
                        for (int i = 0; i < explore.categories.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          _CategoryChip(
                            category: explore.categories[i],
                            isSelected: explore.categories[i].id == explore.selectedCategoryId,
                            onTap: () => ref.read(exploreProvider.notifier).selectCategory(explore.categories[i].id),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 右边36%：固定的更多/Hot/New
          Expanded(
            flex: 36,
            child: Padding(
              key: _rightPanelKey,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 30,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      key: _moreButtonKey,
                      onTap: () => _showMoreCategoriesMenu(context, explore.categories, explore.selectedCategoryId),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            l10n.all,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Image(
                            image: AssetImage('assets/images/more_icon.png'),
                            width: 20,
                            height: 20,
                          ),
                        ],
                      ),
                    ),
                    _FilterTab(label: l10n.hot, isSelected: true, onTap: () {}),
                    _FilterTab(label: 'New', isSelected: false, onTap: () {}),
                  ],
                ),
              ),
            ),
          ),
        ],
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

class _CategoriesDropdown extends StatelessWidget {
  const _CategoriesDropdown({
    required this.categories,
    required this.selectedId,
    required this.left,
    required this.top,
    required this.arrowCenterX,
    required this.barWidth,
    required this.onClose,
    required this.onSelect,
  });

  final List<Category> categories;
  final String selectedId;
  final double left;
  final double top;
  final double arrowCenterX;
  final double barWidth;
  final VoidCallback onClose;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);

    return Stack(
      children: [
        // 点击阴影区域关闭
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: Container(color: Colors.transparent),
          ),
        ),
        // 正三角：直接定位在按钮正下方
        Positioned(
          left: arrowCenterX - 10,
          top: top,
          child: CustomPaint(
            size: const Size(20, 10),
            painter: _UpTrianglePainter(color: const Color(0xFFFFFFFF)),
          ),
        ),
        // 弹框：紧贴三角下方
        Positioned(
          left: left,
          top: top + 10,
          child: Material(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: barWidth,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories.map((cat) {
                    final isSelected = cat.id == selectedId;
                    return GestureDetector(
                      onTap: () => onSelect(cat.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF8F4EFF) : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          cat.localizedName(locale),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UpTrianglePainter extends CustomPainter {
  _UpTrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({required this.label, required this.isSelected, required this.onTap});
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final Category category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8F4EFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          category.localizedName(Localizations.localeOf(context)),
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            fontSize: 13,
          ),
        ),
      ),
    );
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
