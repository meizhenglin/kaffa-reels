import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/app_empty_state.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../home/models/home_card_layout.dart';
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

    final horizontalInset = HomeCardLayout.sectionHorizontalPadding(context);

    final RenderBox moreButtonBox = _moreButtonKey.currentContext!.findRenderObject() as RenderBox;
    final Offset moreButtonOffset = moreButtonBox.localToGlobal(Offset.zero);
    final double arrowCenterX = moreButtonOffset.dx + moreButtonBox.size.width / 2;

    final RenderBox filterBarBox = _filterBarKey.currentContext!.findRenderObject() as RenderBox;
    final Offset filterBarOffset = filterBarBox.localToGlobal(Offset.zero);
    final double filterBarWidth = filterBarBox.size.width;
    // clamp：视口被压到极窄时 filterBarWidth 可能小于左右内边距之和，
    // 算出负宽度传给 SizedBox 会直接炸掉元素树（BoxConstraints 断言）。
    final double dropdownWidth =
        (filterBarWidth - horizontalInset * 2).clamp(0.0, double.infinity);
    final double dropdownLeft = filterBarOffset.dx + horizontalInset;
    final double dropdownTop = moreButtonOffset.dy + moreButtonBox.size.height + HomeCardLayout.scaled(context, 2);

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
              padding: EdgeInsetsDirectional.fromSTEB(
                HomeCardLayout.sectionHorizontalPadding(context),
                HomeCardLayout.scaled(context, 15),
                HomeCardLayout.sectionHorizontalPadding(context),
                HomeCardLayout.scaled(context, 12),
              ),
              child: ExploreSearchBar(
                onTap: () => context.push('/search'),
              ),
            ),
            if (explore.categories.isNotEmpty) ...[
              _buildFilterBar(context, l10n, explore),
              SizedBox(height: HomeCardLayout.scaled(context, 15)),
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
    final chipGap = HomeCardLayout.scaled(context, 10);
    final actionGap = HomeCardLayout.scaled(context, 8);
    final filterBarHeight = HomeCardLayout.scaled(context, 24);

    return SizedBox(
      key: _filterBarKey,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: HomeCardLayout.sectionHorizontalPadding(context),
                end: actionGap,
              ),
              child: ClipRect(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: filterBarHeight),
                    child: Row(
                      children: [
                        for (int i = 0; i < explore.categories.length; i++) ...[
                          if (i > 0) SizedBox(width: chipGap),
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
            padding: EdgeInsetsDirectional.only(
              end: HomeCardLayout.sectionHorizontalPadding(context),
              start: actionGap,
            ),
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
          padding: EdgeInsetsDirectional.fromSTEB(
            HomeCardLayout.gridPadding(context),
            0,
            HomeCardLayout.gridPadding(context),
            HomeCardLayout.gridPadding(context),
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: HomeCardLayout.cardGap(context),
            mainAxisSpacing: HomeCardLayout.cardGap(context),
            childAspectRatio: 106 / 178,
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
                // 【ref.read 而非 ref.watch】这两个值只在点击瞬间需要。
                // 之前每个 item 都 watch 整个 auth/member 状态，用户信息
                // 一刷新（购买后、切 tab、回前台）整页网格全部重建。
                // 在 onTap 回调里 read，语义完全等价但 build 零订阅。
                authState: ref.read(authProvider),
                memberState: ref.read(memberStateProvider),
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
    final triangleHalfWidth = HomeCardLayout.scaled(context, 7);
    final triangleSize = Size(
      HomeCardLayout.scaled(context, 14),
      HomeCardLayout.scaled(context, 10),
    );
    final dropdownTopOffset = HomeCardLayout.scaled(context, 9);
    final dropdownRadius = HomeCardLayout.scaled(context, 12);
    final dropdownPadding = HomeCardLayout.scaled(context, 12);
    final dropdownMaxHeight = HomeCardLayout.scaled(context, 120);
    final dropdownChipGap = HomeCardLayout.scaled(context, 8);
    final dropdownChipRadius = HomeCardLayout.scaled(context, 20);
    final dropdownChipHorizontalPadding = HomeCardLayout.scaled(context, 12);
    final dropdownChipVerticalPadding = HomeCardLayout.scaled(context, 6);
    final dropdownChipFontSize = HomeCardLayout.scaled(context, 13);

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
        PositionedDirectional(
          top: top,
          start: arrowCenterX - triangleHalfWidth,
          child: CustomPaint(
            size: triangleSize,
            painter: _UpTrianglePainter(color: const Color(0xFFFFFFFF)),
          ),
        ),
        // 弹框：紧贴三角下方
        PositionedDirectional(
          top: top + dropdownTopOffset,
          start: left,
          child: Material(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(dropdownRadius),
            child: SizedBox(
              width: barWidth,
              child: Padding(
                padding: EdgeInsets.all(dropdownPadding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: dropdownMaxHeight),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Wrap(
                      spacing: dropdownChipGap,
                      runSpacing: dropdownChipGap,
                      children: categories.map((cat) {
                        final isSelected = cat.id == selectedId;
                        return GestureDetector(
                          onTap: () => onSelect(cat.id),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: dropdownChipHorizontalPadding,
                              vertical: dropdownChipVerticalPadding,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF8F4EFF) : const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(dropdownChipRadius),
                            ),
                            child: Text(
                              cat.localizedName(locale),
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.black87,
                                fontSize: dropdownChipFontSize,
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
    final lineWidth = HomeCardLayout.scaled(context, 16);
    final lineHeight = HomeCardLayout.scaled(context, 2);
    final lineMargin = HomeCardLayout.scaled(context, 1.5);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
        (_) => Container(
          width: lineWidth,
          height: lineHeight,
          margin: EdgeInsets.symmetric(vertical: lineMargin),
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
    final chipHorizontalPadding = HomeCardLayout.scaled(context, 8);
    final chipVerticalPadding = HomeCardLayout.scaled(context, 3);
    final chipRadius = HomeCardLayout.scaled(context, 20);
    final chipFontSize = HomeCardLayout.scaled(context, 13);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: chipHorizontalPadding,
          vertical: chipVerticalPadding,
        ),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8F4EFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(chipRadius),
        ),
        child: Text(
          category.localizedName(Localizations.localeOf(context)),
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            fontSize: chipFontSize,
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final padding = HomeCardLayout.scaled(context, 24);
    final spacing = HomeCardLayout.scaled(context, 16);

    return Center(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            SizedBox(height: spacing),
            FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}
