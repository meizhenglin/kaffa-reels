import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/app_empty_state.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';
import '../../recommend/models/drama.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../models/category.dart';
import '../providers/explore_provider.dart';
import '../widgets/explore_drama_grid_card.dart';
import '../widgets/explore_search_bar.dart';

class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key, this.scrollController});
  final ScrollController? scrollController;

  static void unfocusSearch(BuildContext context) {}

  @override ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  late final ScrollController _scrollController = widget.scrollController ?? ScrollController();
  final _moreButtonKey = GlobalKey();
  final _rightPanelKey = GlobalKey();
  final _filterBarKey = GlobalKey();
  OverlayEntry? _dropdownOverlay;

  @override
  void dispose() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
    if (widget.scrollController == null) _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      final metrics = notification.metrics;
      if (metrics.pixels >= metrics.maxScrollExtent - 240) {
        ref.read(exploreProvider.notifier).loadMore();
      }
    }
    return false;
  }

  Future<void> _onRefresh() async {
    await ref.read(exploreProvider.notifier).refresh();
  }

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
    final double dropdownTop = moreButtonOffset.dy + moreButtonBox.size.height + 2;

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

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 15, 16, 12),
              child: ExploreSearchBar(
                onTap: () => context.push('/search'),
              ),
            ),
            if (explore.categories.isNotEmpty) ...[
              _buildFilterBar(context, l10n, explore),
              const SizedBox(height: 15),
            ],
            Expanded(
              child: _buildContent(
                context,
                l10n,
                dramas: explore.dramas,
                isLoading: explore.isLoading && !explore.hasData,
                isLoadingMore: explore.isLoadingMore,
                explore: explore,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 筛选栏：左侧滚动分类，右侧仅保留更多按钮
  Widget _buildFilterBar(BuildContext context, AppLocalizations l10n, ExploreState explore) {
    return SizedBox(
      key: _filterBarKey,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
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
                            isSelected:
                                explore.categories[i].id ==
                                explore.selectedCategoryId,
                            onTap: () => ref
                                .read(exploreProvider.notifier)
                                .selectCategory(explore.categories[i].id),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            key: _rightPanelKey,
            padding: const EdgeInsetsDirectional.only(end: 16, start: 8),
            child: GestureDetector(
              key: _moreButtonKey,
              onTap: () => _showMoreCategoriesMenu(
                context,
                explore.categories,
                explore.selectedCategoryId,
              ),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(
                width: 28,
                height: 28,
                child: Center(child: _MoreMenuIcon()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n, {
    required List<Drama> dramas,
    required bool isLoading,
    required bool isLoadingMore,
    required ExploreState explore,
  }) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (explore.hasError && dramas.isEmpty) {
      return _ErrorView(
        message: explore.errorMessage ?? l10n.unknownError,
        onRetry: () => ref.read(exploreProvider.notifier).refresh(),
      );
    }
    if (dramas.isEmpty) {
      return AppEmptyState(
        message: l10n.noDataAvailableAtTheMoment,
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: GridView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.64,
          ),
          itemCount: dramas.length + (isLoadingMore ? 2 : 0),
          itemBuilder: (context, index) {
            if (index >= dramas.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final drama = dramas[index];
            return ExploreDramaGridCard(
              drama: drama,
              onTap: () => openDramaPlayerWithVipCheck(
                context: context,
                drama: drama,
                authState: ref.watch(authProvider),
                memberState: ref.watch(memberStateProvider),
              ),
            );
          },
        ),
      ),
    );
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
    const dropdownMaxHeight = 120.0;

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
        PositionedDirectional(
          top: top,
          start: arrowCenterX - 7,
          child: CustomPaint(
            size: const Size(14, 10),
            painter: _UpTrianglePainter(color: const Color(0xFFFFFFFF)),
          ),
        ),
        // 弹框：紧贴三角下方
        PositionedDirectional(
          top: top + 9,
          start: left,
          child: Material(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: barWidth,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: dropdownMaxHeight),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
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
      ..lineTo(size.width / 2, size.height * 0.08)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MoreMenuIcon extends StatelessWidget {
  const _MoreMenuIcon();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
        (_) => Container(
          width: 16,
          height: 2,
          margin: const EdgeInsets.symmetric(vertical: 1.5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
          ),
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
