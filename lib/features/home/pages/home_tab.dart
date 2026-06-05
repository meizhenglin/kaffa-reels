import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../components/preload_network_image.dart';
import '../../../core/utils/localized_badge_assets.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';
import '../../recommend/models/banner.dart';
import '../../recommend/models/drama.dart';
import '../../recommend/providers/recommend_provider.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../../recommend/widgets/banner_carousel.dart';
import '../mixins/tab_scroll_mixin.dart';
import '../models/home_card_layout.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> with TabScrollMixin {
  @override
  String get tabId => 'home';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(recommendProvider.notifier).loadHomeSections();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recommendState = ref.watch(recommendProvider);

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: CustomScrollView(
        controller: tabScrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: BannerCarousel(
              banners: recommendState.banners.isNotEmpty
                  ? recommendState.banners
                  : recommendState.isLoading
                      ? [preloadBanner]
                      : _buildMockBanners(),
              height: 540,
              onBannerTap: (banner) => _onBannerTap(banner),
              onSearchTap: () => context.push('/search'),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildSection(
              context,
              title: l10n.topRecommend,
              onViewAll: () => context.push('/recommend/hot'),
              topPadding: 30,
              // bottomPadding: 0,
            ),
          ),
          SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: HomeCardLayout.scaled(context, 30)),
                child: SizedBox(
                  height: HomeCardLayout.smallCardHeight(context) + HomeCardLayout.scaled(context, 25),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(
                      horizontal: HomeCardLayout.sectionHorizontalPadding(context),
                    ),
                  itemCount: recommendState.topRecommend.isNotEmpty
                      ? recommendState.topRecommend.length.clamp(0, 5)
                      : 5,
                  itemBuilder: (context, index) {
                    final drama = recommendState.topRecommend.isNotEmpty
                        ? recommendState.topRecommend[index]
                        : null;
                    return _buildHorizontalCard(
                      context,
                      index,
                      drama,
                      onTap: drama != null
                          ? () => openDramaPlayerWithVipCheck(
                                context: context,
                                drama: drama,
                                authState: ref.watch(authProvider),
                                memberState: ref.watch(memberStateProvider),
                              )
                          : null,
                    );
                  },
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildSection(
              context,
              title: l10n.newForThisMonth,
              onViewAll: () => context.push('/recommend/new'),
              topPadding: 0,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                HomeCardLayout.sectionHorizontalPadding(context),
                0,
                HomeCardLayout.sectionHorizontalPadding(context),
                0,
              ),
              child: _buildNewForThisMonthSection(context, recommendState),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildSection(
              context,
              title: l10n.vipZone,
              onViewAll: () => context.push('/recommend/vip'),
              topPadding: 30,
            ),
          ),
          SliverPadding(
            padding: EdgeInsetsDirectional.fromSTEB(
              HomeCardLayout.sectionHorizontalPadding(context),
              0,
              HomeCardLayout.sectionHorizontalPadding(context),
              0,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                childAspectRatio: 106 / 150,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final drama = recommendState.vipZone.isNotEmpty &&
                          index < recommendState.vipZone.length
                      ? recommendState.vipZone[index]
                      : null;
                  return _buildVipCard(
                    context,
                    recommendState,
                    index,
                    onTap: drama != null
                        ? () => openDramaPlayerWithVipCheck(
                              context: context,
                              drama: drama,
                              authState: ref.watch(authProvider),
                              memberState: ref.watch(memberStateProvider),
                            )
                        : null,
                  );
                },
                childCount: recommendState.vipZone.isNotEmpty
                    ? recommendState.vipZone.length.clamp(0, 6)
                    : 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onRefresh() async {
    await ref.read(recommendProvider.notifier).loadHomeSections(refresh: true);
  }

  List<BannerItem> _buildMockBanners() {
    return [
      const BannerItem(
        id: 'banner_1',
        imageUrl: 'https://picsum.photos/seed/banner1/800/400',
        dramaId: 'drama_0',
        // title: 'Desert Rose / وردة الصحراء',
      ),
      const BannerItem(
        id: 'banner_2',
        imageUrl: 'https://picsum.photos/seed/banner2/800/400',
        dramaId: 'drama_5',
        title: 'The Shadow / الظل',
      ),
      const BannerItem(
        id: 'banner_3',
        imageUrl: 'https://picsum.photos/seed/banner3/800/400',
        dramaId: 'drama_10',
        title: 'The Mix-Up / الخلط',
      ),
    ];
  }

  Future<void> _onBannerTap(BannerItem banner) async {
    final drama = await ref
        .read(recommendProvider.notifier)
        .getDramaById(banner.dramaId);
    if (drama != null && mounted) {
      openDramaPlayerWithVipCheck(
        context: context,
        drama: drama,
        authState: ref.watch(authProvider),
        memberState: ref.watch(memberStateProvider),
      );
    }
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required VoidCallback onViewAll,
    double topPadding = 15,
    double bottomPadding = 15,
  }) {
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        HomeCardLayout.sectionHorizontalPadding(context),
        HomeCardLayout.scaled(context, topPadding),
        HomeCardLayout.sectionHorizontalPadding(context),
        HomeCardLayout.scaled(context, bottomPadding),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: HomeCardLayout.scaled(context, 16),
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Image.asset(
              'assets/images/more_icon.png',
              width: HomeCardLayout.scaled(context, 20),
              height: HomeCardLayout.scaled(context, 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewForThisMonthSection(
    BuildContext context,
    RecommendState state,
  ) {
    const visibleCount = 4;
    final items = state.newForThisMonth.isNotEmpty
        ? state.newForThisMonth.take(visibleCount).toList()
        : List<Drama?>.filled(visibleCount, null);

    return Column(
      children: List.generate(2, (rowIndex) {
        final leftIndex = rowIndex * 2;
        final rightIndex = leftIndex + 1;

        return Padding(
          padding: EdgeInsetsDirectional.only(
            bottom: rowIndex == 0 ? HomeCardLayout.cardGap(context) : 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDramaCardFromDrama(
                context,
                items[leftIndex],
                leftIndex,
                onTap: items[leftIndex] != null
                    ? () => openDramaPlayerWithVipCheck(
                          context: context,
                          drama: items[leftIndex]!,
                          authState: ref.watch(authProvider),
                          memberState: ref.watch(memberStateProvider),
                        )
                    : null,
              ),
              _buildDramaCardFromDrama(
                context,
                items[rightIndex],
                rightIndex,
                onTap: items[rightIndex] != null
                    ? () => openDramaPlayerWithVipCheck(
                          context: context,
                          drama: items[rightIndex]!,
                          authState: ref.watch(authProvider),
                          memberState: ref.watch(memberStateProvider),
                        )
                    : null,
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildDramaCardFromDrama(
    BuildContext context,
    Drama? drama,
    int index, {
    VoidCallback? onTap,
  }) {
    final coverUrl = drama?.coverUrl;
    final vipBadgeAsset = localizedHomeVipBadgeAsset(context);

    final cardWidth = HomeCardLayout.largeCardWidth(context);
    final cardHeight = HomeCardLayout.largeCardHeight(context);

    return SizedBox(
      width: cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(HomeCardLayout.largeCardRadius(context)),
                  child: PreloadNetworkImage(
                    imageUrl: coverUrl ?? '',
                    preloadAsset: 'assets/images/small_preload_bg.png',
                    width: cardWidth,
                    height: cardHeight,
                    fit: BoxFit.cover,
                  ),
                ),
                if (drama != null && drama.isVipOnly)
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
          SizedBox(height: HomeCardLayout.scaled(context, 8)),
          Text(
            drama?.title.split(' / ').first ?? 'Drama ${index + 1}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildVipCard(
    BuildContext context,
    RecommendState state,
    int index, {
    VoidCallback? onTap,
  }) {
    // VIP Zone 使用 vipZone 数据
    final drama = state.vipZone.isNotEmpty && index < state.vipZone.length
        ? state.vipZone[index]
        : null;
    final coverUrl = drama?.coverUrl;
    final vipBadgeAsset = localizedHomeVipBadgeAsset(context);
    final cardWidth = HomeCardLayout.smallCardWidth(context);
    final cardHeight = HomeCardLayout.smallCardHeight(context);

    return SizedBox(
      width: cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(HomeCardLayout.smallCardRadius(context)),
                    child: PreloadNetworkImage(
                      imageUrl: coverUrl ?? '',
                      preloadAsset: 'assets/images/small_preload_bg.png',
                      width: cardWidth,
                      height: cardHeight,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (drama != null && drama.isVipOnly)
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
          ),
          SizedBox(height: HomeCardLayout.scaled(context, 8)),
          Text(
            drama?.title.split(' / ').first ?? 'VIP Drama ${index + 1}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalCard(
    BuildContext context,
    int index,
    Drama? drama, {
    VoidCallback? onTap,
  }) {
    final coverUrl = drama?.coverUrl;
    final rankBadgeAsset = localizedTopRankBadgeAsset(context, index + 1);
    final cardWidth = HomeCardLayout.smallCardWidth(context);
    final cardHeight = HomeCardLayout.smallCardHeight(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(end: HomeCardLayout.cardGap(context)),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: onTap,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(HomeCardLayout.smallCardRadius(context)),
                    child: PreloadNetworkImage(
                      imageUrl: coverUrl ?? '',
                      preloadAsset: 'assets/images/small_preload_bg.png',
                      width: cardWidth,
                      height: cardHeight,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (drama != null && index < 5)
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
            ),
            SizedBox(height: HomeCardLayout.scaled(context, 6)),
            Text(
              drama?.title.split(' / ').first ?? 'Drama ${index + 1}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
