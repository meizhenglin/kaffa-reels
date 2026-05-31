import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';
import '../../recommend/models/banner.dart';
import '../../recommend/models/drama.dart';
import '../../recommend/providers/recommend_provider.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../../recommend/widgets/banner_carousel.dart';
import '../mixins/tab_scroll_mixin.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> with TabScrollMixin {
  @override
  String get tabId => 'home';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recommendState = ref.watch(recommendProvider);

    if (recommendState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

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
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                itemCount: recommendState.hotPicks.isNotEmpty
                    ? recommendState.hotPicks.length.clamp(0, 5)
                    : 5,
                itemBuilder: (context, index) {
                  final drama = recommendState.hotPicks.isNotEmpty
                      ? recommendState.hotPicks[index]
                      : null;
                  return _buildHorizontalCard(context, index, drama);
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildSection(
              context,
              title: l10n.newForThisMonth,
              onViewAll: () => context.push('/recommend/all'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                childAspectRatio: 165 / 224,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildDramaCard(
                  context,
                  recommendState,
                  index,
                  isNewThisMonth: true,
                ),
                childCount: 4,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildSection(
              context,
              title: l10n.vipZone,
              onViewAll: () => context.go('/membership'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                childAspectRatio: 106 / 150,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _buildVipCard(context, recommendState, index),
                childCount: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onRefresh() async {
    await ref.read(recommendProvider.notifier).refresh();
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
  }) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 14, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Image.asset(
              'assets/images/more_icon.png',
              width: 20,
              height: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDramaCard(
    BuildContext context,
    RecommendState state,
    int index, {
    bool isNewThisMonth = false,
  }) {
    final source = isNewThisMonth
        ? state.newEpisodes
        : state.newEpisodes;
    final drama = source.isNotEmpty && index < source.length
        ? source[index]
        : null;
    final coverUrl = drama?.coverUrl;

    return SizedBox(
      width: 165,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: drama != null
                  ? () => openDramaPlayerWithVipCheck(
                        context: context,
                        drama: drama,
                        authState: ref.watch(authProvider),
                        memberState: ref.watch(memberStateProvider),
                      )
                  : null,
              child: coverUrl == null
                  ? const Center(
                      child: Icon(
                        Icons.movie_outlined,
                        size: 40,
                        color: Colors.white54,
                      ),
                    )
                  : Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(16),
                            image: DecorationImage(
                                    image: NetworkImage(coverUrl),
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        // VIP 角标（仅 isVipOnly 显示）
                        if (drama != null && drama.isVipOnly)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: Image.asset(
                              'assets/images/home_vip_icon.png',
                              width: 42,
                              height: 18,
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            drama?.title.split(' / ').first ?? 'Drama ${index + 1}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // if (drama != null)
          //   Text(
          //     '${drama.formattedViews} views • ${drama.episodeCount} episodes',
          //     style: Theme.of(context).textTheme.bodySmall?.copyWith(
          //       color: Colors.white60,
          //       fontSize: 10,
          //     ),
          //     maxLines: 1,
          //     overflow: TextOverflow.ellipsis,
          //   ),
        ],
      ),
    );
  }

  Widget _buildVipCard(BuildContext context, RecommendState state, int index) {
    // VIP 使用热门数据
    final drama = state.hotPicks.isNotEmpty && index < state.hotPicks.length
        ? state.hotPicks[index]
        : null;
    final coverUrl = drama?.coverUrl;

    return SizedBox(
      width: 106,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: drama != null
                  ? () => openDramaPlayerWithVipCheck(
                        context: context,
                        drama: drama,
                        authState: ref.watch(authProvider),
                        memberState: ref.watch(memberStateProvider),
                      )
                  : null,
              child: Stack(
                children: [
                  coverUrl != null
                      ? Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(16),
                            image: DecorationImage(
                              image: NetworkImage(coverUrl),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.star,
                              size: 30,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                  // VIP 徽章（强制显示，左上角）
                  if (drama != null && drama.isVipOnly)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Image.asset(
                        'assets/images/home_vip_icon.png',
                        width: 42,
                        height: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
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

  Widget _buildBadgeOverlay(Drama? drama) {
    if (drama?.badge == null) return const SizedBox.shrink();

    Color badgeColor;
    String badgeText;

    switch (drama!.badge!.name) {
      case 'hot':
        badgeColor = Colors.red;
        badgeText = 'HOT';
        break;
      case 'update':
        badgeColor = Colors.green;
        badgeText = 'NEW';
        break;
      case 'exclusive':
        badgeColor = Colors.purple;
        badgeText = 'VIP';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          badgeText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalCard(BuildContext context, int index, Drama? drama) {
    final coverUrl = drama?.coverUrl;

    return Padding(
      padding: const EdgeInsets.only(right: 15),
      child: SizedBox(
        width: 106,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: drama != null
                  ? () => openDramaPlayerWithVipCheck(
                        context: context,
                        drama: drama,
                        authState: ref.watch(authProvider),
                        memberState: ref.watch(memberStateProvider),
                      )
                  : null,
              child: Stack(
                children: [
                  coverUrl != null
                      ? Container(
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(16),
                            image: DecorationImage(
                              image: NetworkImage(coverUrl),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      : Container(
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.movie_outlined,
                              size: 40,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                  // 前5名角标
                  if (drama != null && index < 5)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Image.asset(
                        'assets/images/top_${index + 1}_icon.png',
                        width: 22,
                        height: 22,
                      ),
                    ),
                  // VIP 角标（仅非前3名显示）
                  // if (drama != null && drama.isVipOnly && index >= 3)
                  //   Positioned(
                  //     top: 4,
                  //     left: 4,
                  //     child: Container(
                  //       padding: const EdgeInsets.all(2),
                  //       decoration: BoxDecoration(
                  //         color: Colors.amber.withValues(alpha: 0.9),
                  //         borderRadius: BorderRadius.circular(4),
                  //       ),
                  //       child: const Icon(Icons.star, size: 12, color: Colors.white),
                  //     ),
                  //   ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              drama?.title.split(' / ').first ?? 'Drama ${index + 1}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // if (drama != null)
            //   Text(
            //     drama.formattedViews,
            //     style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60, fontSize: 10),
            //     maxLines: 1,
            //   ),
          ],
        ),
      ),
    );
  }
}
