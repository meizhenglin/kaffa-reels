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
    // 【select 只订阅需要的字段】recommendProvider 是 7 个列表 + 15 个分页
    // 标志的巨型 state：推荐页每翻一页都会 copyWith 出一个新 state，
    // watch 整个 provider 会让首页（Banner + 3 个 section）跟着全量重建。
    // select 之后只有对应列表的数据本身变化才会触发重建。
    final banners = ref.watch(
      recommendProvider.select((s) => s.banners),
    );
    final topRecommend = ref.watch(
      recommendProvider.select((s) => s.topRecommend),
    );
    final newForThisMonth = ref.watch(
      recommendProvider.select((s) => s.newForThisMonth),
    );
    final vipZone = ref.watch(recommendProvider.select((s) => s.vipZone));
    // 【不 watch auth/member】这两个状态只在点击回调里需要（见 openDramaPlayerWithVipCheck）。
    // 之前 watch 整个 authProvider：用户信息一刷新（购买后、切 tab、回前台），
    // 整个首页 CustomScrollView（Banner + 3 个 section + 几十张封面）全量重建。
    // 现在回调里 ref.read，build 路径零订阅。

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
              banners: banners.isNotEmpty ? banners : [preloadBanner],
              height: HomeCardLayout.scaled(context, 540),
              onBannerTap: (banner) => _onBannerTap(banner),
              onSearchTap: () => context.push('/search'),
            ),
          ),
          SliverToBoxAdapter(
            child: _HomeSectionHeader(
              title: l10n.topRecommend,
              onViewAll: () => context.push('/recommend/hot'),
              topPadding: 30,
            ),
          ),
          SliverToBoxAdapter(
            child: _TopRecommendList(
              dramas: topRecommend,
              onTapDrama: (drama) => openDramaPlayerWithVipCheck(
                context: context,
                drama: drama,
                authState: ref.read(authProvider),
                memberState: ref.read(memberStateProvider),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _HomeSectionHeader(
              title: l10n.newForThisMonth,
              onViewAll: () => context.push('/recommend/new'),
              topPadding: 0,
            ),
          ),
          SliverToBoxAdapter(
            child: _NewForThisMonthGrid(
              dramas: newForThisMonth,
              onTapDrama: (drama) => openDramaPlayerWithVipCheck(
                context: context,
                drama: drama,
                authState: ref.read(authProvider),
                memberState: ref.read(memberStateProvider),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _HomeSectionHeader(
              title: l10n.vipZone,
              onViewAll: () => context.push('/recommend/vip'),
              topPadding: 30,
            ),
          ),
          SliverToBoxAdapter(
            child: _VipZoneGrid(
              dramas: vipZone,
              onTapDrama: (drama) => openDramaPlayerWithVipCheck(
                context: context,
                drama: drama,
                authState: ref.read(authProvider),
                memberState: ref.read(memberStateProvider),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: HomeCardLayout.scaled(context, 18)),
          ),
        ],
      ),
    );
  }

  Future<void> _onRefresh() async {
    await ref.read(recommendProvider.notifier).loadHomeSections(refresh: true);
  }


  Future<void> _onBannerTap(BannerItem banner) async {
    final drama = await ref
        .read(recommendProvider.notifier)
        .getDramaById(banner.dramaId);
    if (drama != null && mounted) {
      openDramaPlayerWithVipCheck(
        context: context,
        drama: drama,
        authState: ref.read(authProvider),
        memberState: ref.read(memberStateProvider),
      );
    }
  }

}

class _HomeDramaCard extends StatelessWidget {
  const _HomeDramaCard({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.title,
    required this.imageUrl,
    this.titleSpacing = 8,
    this.overlayBadge,
    this.cornerBadge,
    this.onTap,
  });

  final double width;
  final double height;
  final double borderRadius;
  final String title;
  final String imageUrl;
  final double titleSpacing;
  final Widget? overlayBadge;
  final Widget? cornerBadge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final image = GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: PreloadNetworkImage(
              imageUrl: imageUrl,
              preloadAsset: 'assets/images/small_preload_bg.png',
              width: width,
              height: height,
              fit: BoxFit.cover,
            ),
          ),
          if (overlayBadge != null)
            PositionedDirectional(
              top: 0,
              start: 0,
              child: overlayBadge!,
            ),
          if (cornerBadge != null)
            PositionedDirectional(
              top: 0,
              start: 0,
              child: cornerBadge!,
            ),
        ],
      ),
    );

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          image,
          SizedBox(height: titleSpacing),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    required this.title,
    required this.onViewAll,
    this.topPadding = 15,
  });

  final String title;
  final VoidCallback onViewAll;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        HomeCardLayout.sectionHorizontalPadding(context),
        HomeCardLayout.scaled(context, topPadding),
        HomeCardLayout.sectionHorizontalPadding(context),
        HomeCardLayout.scaled(context, 15),
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
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
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
}

class _TopRecommendList extends StatelessWidget {
  const _TopRecommendList({
    required this.dramas,
    required this.onTapDrama,
  });

  final List<Drama> dramas;
  final ValueChanged<Drama> onTapDrama;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: HomeCardLayout.scaled(context, 30)),
      child: SizedBox(
        height: HomeCardLayout.smallCardTotalHeight(context),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: HomeCardLayout.sectionHorizontalPadding(context),
          ),
          itemCount: dramas.isNotEmpty ? dramas.length.clamp(0, 5) : 5,
          separatorBuilder: (_, __) => SizedBox(width: HomeCardLayout.cardGap(context)),
          itemBuilder: (context, index) {
            final drama = dramas.isNotEmpty ? dramas[index] : null;
            return _TopRecommendCard(
              drama: drama,
              index: index,
              onTap: drama != null ? () => onTapDrama(drama) : null,
            );
          },
        ),
      ),
    );
  }
}

class _TopRecommendCard extends StatelessWidget {
  const _TopRecommendCard({
    required this.drama,
    required this.index,
    this.onTap,
  });

  final Drama? drama;
  final int index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _HomeDramaCard(
      width: HomeCardLayout.smallCardWidth(context),
      height: HomeCardLayout.smallCardHeight(context),
        borderRadius: HomeCardLayout.smallCardRadius(context),
        title: drama?.title.split(' / ').first ?? 'Drama ${index + 1}',
        imageUrl: drama?.coverUrl ?? '',
        titleSpacing: HomeCardLayout.scaled(context, 6),
        overlayBadge: drama != null && index < 5
            ? _HomeCardBadge(
                assetPath: localizedTopRankBadgeAsset(context, index + 1),
                width: HomeCardLayout.scaled(context, 22),
                height: HomeCardLayout.scaled(context, 22),
              )
            : null,
        onTap: onTap,
      );
  }
}

class _NewForThisMonthGrid extends StatelessWidget {
  const _NewForThisMonthGrid({
    required this.dramas,
    required this.onTapDrama,
  });

  final List<Drama> dramas;
  final ValueChanged<Drama> onTapDrama;

  @override
  Widget build(BuildContext context) {
    const visibleCount = 4;
    final items = dramas.isNotEmpty
        ? dramas.take(visibleCount).toList()
        : List<Drama?>.filled(visibleCount, null);

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        HomeCardLayout.sectionHorizontalPadding(context),
        0,
        HomeCardLayout.sectionHorizontalPadding(context),
        0,
      ),
      child: Column(
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
                _NewForThisMonthCard(
                  drama: items[leftIndex],
                  index: leftIndex,
                  onTap: items[leftIndex] != null
                      ? () => onTapDrama(items[leftIndex]!)
                      : null,
                ),
                _NewForThisMonthCard(
                  drama: items[rightIndex],
                  index: rightIndex,
                  onTap: items[rightIndex] != null
                      ? () => onTapDrama(items[rightIndex]!)
                      : null,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _NewForThisMonthCard extends StatelessWidget {
  const _NewForThisMonthCard({
    required this.drama,
    required this.index,
    this.onTap,
  });

  final Drama? drama;
  final int index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _HomeDramaCard(
      width: HomeCardLayout.largeCardWidth(context),
      height: HomeCardLayout.largeCardHeight(context),
      borderRadius: HomeCardLayout.largeCardRadius(context),
      title: drama?.title.split(' / ').first ?? 'Drama ${index + 1}',
      imageUrl: drama?.coverUrl ?? '',
      titleSpacing: HomeCardLayout.scaled(context, 8),
      cornerBadge: drama != null && drama!.videoAccessType == 1
          ? _HomeCardBadge(
              assetPath: localizedHomeVipBadgeAsset(context),
              width: HomeCardLayout.scaled(context, 42),
              height: HomeCardLayout.scaled(context, 18),
            )
          : null,
      onTap: onTap,
    );
  }
}

class _VipZoneGrid extends StatelessWidget {
  const _VipZoneGrid({
    required this.dramas,
    required this.onTapDrama,
  });

  final List<Drama> dramas;
  final ValueChanged<Drama> onTapDrama;

  @override
  Widget build(BuildContext context) {
    const visibleCount = 6;
    final items = dramas.isNotEmpty
        ? dramas.take(visibleCount).toList()
        : List<Drama?>.filled(visibleCount, null);

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        HomeCardLayout.sectionHorizontalPadding(context),
        0,
        HomeCardLayout.sectionHorizontalPadding(context),
        0,
      ),
      child: Column(
        children: List.generate(2, (rowIndex) {
          final startIndex = rowIndex * 3;

          return Padding(
            padding: EdgeInsetsDirectional.only(
              bottom: rowIndex == 0 ? HomeCardLayout.cardGap(context) : 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(3, (columnIndex) {
                final itemIndex = startIndex + columnIndex;
                final drama = items[itemIndex];

                return _VipZoneCard(
                  drama: drama,
                  index: itemIndex,
                  onTap: drama != null ? () => onTapDrama(drama) : null,
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}

class _VipZoneCard extends StatelessWidget {
  const _VipZoneCard({
    required this.drama,
    required this.index,
    this.onTap,
  });

  final Drama? drama;
  final int index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _HomeDramaCard(
      width: HomeCardLayout.smallCardWidth(context),
      height: HomeCardLayout.smallCardHeight(context),
      borderRadius: HomeCardLayout.smallCardRadius(context),
      title: drama?.title.split(' / ').first ?? 'VIP Drama ${index + 1}',
      imageUrl: drama?.coverUrl ?? '',
      titleSpacing: HomeCardLayout.scaled(context, 8),
      cornerBadge: drama != null && drama!.videoAccessType == 1
          ? _HomeCardBadge(
              assetPath: localizedHomeVipBadgeAsset(context),
              width: HomeCardLayout.scaled(context, 42),
              height: HomeCardLayout.scaled(context, 18),
            )
          : null,
      onTap: onTap,
    );
  }
}

class _HomeCardBadge extends StatelessWidget {
  const _HomeCardBadge({
    required this.assetPath,
    required this.width,
    required this.height,
  });

  final String assetPath;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
    );
  }
}
