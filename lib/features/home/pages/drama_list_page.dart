import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/app_empty_state.dart';
import '../../../components/preload_network_image.dart';
import '../../../components/rtl_back_button.dart';
import '../../../core/utils/localized_badge_assets.dart';
import '../../../l10n/app_localizations.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../models/home_card_layout.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';
import '../../recommend/models/drama.dart';
import '../../recommend/models/drama_list_type.dart';
import '../../recommend/providers/recommend_provider.dart';
import '../../recommend/utils/drama_navigation.dart';

/// 短剧列表页面
///
/// 支持展示热门短剧列表和全部推荐列表，通过 [DramaListType] 区分
class DramaListPage extends ConsumerStatefulWidget {
  const DramaListPage({
    super.key,
    required this.type,
  });

  final DramaListType type;

  @override
  ConsumerState<DramaListPage> createState() => _DramaListPageState();
}

class _DramaListPageState extends ConsumerState<DramaListPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  String _title(AppLocalizations l10n) {
    switch (widget.type) {
      case DramaListType.topRecommend:
        return l10n.topRecommend;
      case DramaListType.newForThisMonth:
        return l10n.newForThisMonth;
      case DramaListType.vipZone:
        return l10n.vipZone;
      case DramaListType.recommended:
        return l10n.allRecommended;
    }
  }

  List<Drama> _dramas(RecommendState state) {
    switch (widget.type) {
      case DramaListType.topRecommend:
        return state.topRecommend;
      case DramaListType.newForThisMonth:
        return state.newForThisMonth;
      case DramaListType.vipZone:
        return state.vipZone;
      case DramaListType.recommended:
        return state.newEpisodes;
    }
  }

  Future<void> _onRefresh() {
    return ref.read(recommendProvider.notifier).refreshDramaList(widget.type);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      ref.read(recommendProvider.notifier).loadMoreDramaList(widget.type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recommendState = ref.watch(recommendProvider);
    final dramas = _dramas(recommendState);
    final isLoading = recommendState.isLoading && dramas.isEmpty;

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, l10n),
            Expanded(
              child: _buildBody(context, dramas, isLoading, recommendState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: HomeCardLayout.sectionHorizontalPadding(context),
        vertical: HomeCardLayout.scaled(context, 8),
      ),
      child: Row(
        children: [
          RtlBackButton(
            color: Colors.white,
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Text(
              _title(l10n),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: HomeCardLayout.scaled(context, 17),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: HomeCardLayout.scaled(context, 24)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<Drama> dramas,
    bool isLoading,
    RecommendState state,
  ) {
    final isLoadingMore = switch (widget.type) {
      DramaListType.topRecommend => state.isTopRecommendLoadingMore,
      DramaListType.newForThisMonth => state.isNewForThisMonthLoadingMore,
      DramaListType.vipZone => state.isVipZoneLoadingMore,
      DramaListType.recommended => state.isLoadingMore,
    };

    final gridGap = HomeCardLayout.cardGap(context);
    final gridPadding = HomeCardLayout.gridPadding(context);

    if (isLoading) {
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.all(gridPadding),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: gridGap,
          crossAxisSpacing: gridGap,
          childAspectRatio: 106 / 178,
        ),
        itemCount: 9,
        itemBuilder: (context, index) => _buildLoadingCard(context, index),
      );
    }

    if (dramas.isEmpty) {
      return AppEmptyState(message: AppLocalizations.of(context).noDataAvailableAtTheMoment);
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: GridView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.all(gridPadding),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: gridGap,
          crossAxisSpacing: gridGap,
          childAspectRatio: 106 / 178,
        ),
        itemCount: dramas.length + (isLoadingMore ? 3 : 0),
        itemBuilder: (context, index) {
          if (index >= dramas.length) {
            return _buildLoadingCard(context, index);
          }

          final drama = dramas[index];
          return _buildCard(
            context,
            ref,
            index,
            drama,
          );
        },
      ),
    );
  }

  Widget _buildLoadingCard(BuildContext context, int index) {
    final rankBadgeAsset = localizedTopRankBadgeAsset(context, index + 1);
    final cardWidth = HomeCardLayout.smallCardWidth(context);
    final cardHeight = HomeCardLayout.smallCardHeight(context);

    return SizedBox(
      width: cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(HomeCardLayout.smallCardRadius(context)),
                child: Image.asset(
                  'assets/images/small_preload_bg.png',
                  width: cardWidth,
                  height: cardHeight,
                  fit: BoxFit.cover,
                ),
              ),
              if (widget.type == DramaListType.topRecommend && index < 5)
                PositionedDirectional(
                  top: 0,
                  start: 0,
                  child: Image.asset(
                    rankBadgeAsset,
                    width: HomeCardLayout.scaled(context, 22),
                    height: HomeCardLayout.scaled(context, 22),
                  ),
                ),
            ],
          ),
          SizedBox(height: HomeCardLayout.scaled(context, 5)),
          Container(
            width: HomeCardLayout.scaled(context, 80),
            height: HomeCardLayout.scaled(context, 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref,
    int index,
    Drama drama,
  ) {
    final coverUrl = drama.coverUrl;
    final rankBadgeAsset = localizedTopRankBadgeAsset(context, index + 1);
    final vipBadgeAsset = localizedHomeVipBadgeAsset(context);
    final cardWidth = HomeCardLayout.smallCardWidth(context);
    final cardHeight = HomeCardLayout.smallCardHeight(context);
    final showRankBadge = widget.type == DramaListType.topRecommend && index < 5;
    final showVipBadge =
        (widget.type == DramaListType.newForThisMonth ||
            widget.type == DramaListType.vipZone) &&
        drama.videoAccessType == 1;

    return SizedBox(
      width: cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => openDramaPlayerWithVipCheck(
              context: context,
              drama: drama,
              authState: ref.watch(authProvider),
              memberState: ref.watch(memberStateProvider),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(HomeCardLayout.smallCardRadius(context)),
                  child: PreloadNetworkImage(
                    imageUrl: coverUrl,
                    preloadAsset: 'assets/images/small_preload_bg.png',
                    width: cardWidth,
                    height: cardHeight,
                    fit: BoxFit.cover,
                  ),
                ),
                if (showRankBadge)
                  PositionedDirectional(
                    top: 0,
                    start: 0,
                    child: Image.asset(
                      rankBadgeAsset,
                      width: HomeCardLayout.scaled(context, 22),
                      height: HomeCardLayout.scaled(context, 22),
                    ),
                  ),
                if (showVipBadge)
                  PositionedDirectional(
                    top: 0,
                    start: 0,
                    child: Image.asset(
                      vipBadgeAsset,
                      width: HomeCardLayout.scaled(context, 42),
                      height: HomeCardLayout.scaled(context, 18),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: HomeCardLayout.scaled(context, 5)),
          Text(
            drama.title.split(' / ').first,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontSize: HomeCardLayout.scaled(context, 13),
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
