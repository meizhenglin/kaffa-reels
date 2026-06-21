import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/app_empty_state.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/preload_network_image.dart';
import '../../../components/rtl_back_button.dart';
import '../../../core/utils/localized_badge_assets.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../../home/models/home_card_layout.dart';
import '../../payment/providers/membership_provider.dart';
import '../../recommend/models/drama.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../providers/history_provider.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(() => ref.read(historyProvider.notifier).loadInitial());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      ref.read(historyProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final l10n = AppLocalizations.of(context);

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, l10n),
            Expanded(
              child: _buildBody(context, history, l10n),
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
              l10n.watchHistory,
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
    HistoryState history,
    AppLocalizations l10n,
  ) {
    final gridGap = HomeCardLayout.cardGap(context);
    final gridPadding = HomeCardLayout.gridPadding(context);

    if (history.isLoading && history.items.isEmpty) {
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
        itemBuilder: (context, index) => _buildLoadingCard(context),
      );
    }

    if (history.isEmpty) {
      return AppEmptyState(message: l10n.noDataAvailableAtTheMoment);
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(historyProvider.notifier).refresh(),
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
        itemCount: history.items.length + (history.isLoadingMore ? 3 : 0),
        itemBuilder: (context, index) {
          if (index >= history.items.length) {
            return _buildLoadingCard(context);
          }

          return _buildDramaCard(context, history.items[index]);
        },
      ),
    );
  }

  Widget _buildLoadingCard(BuildContext context) {
    final cardWidth = HomeCardLayout.smallCardWidth(context);
    final cardHeight = HomeCardLayout.smallCardHeight(context);

    return SizedBox(
      width: cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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

  Widget _buildDramaCard(BuildContext context, Drama drama) {
    final authState = ref.watch(authProvider);
    final memberState = ref.watch(memberStateProvider);
    final coverUrl = drama.coverUrl;
    final vipBadgeAsset = localizedHomeVipBadgeAsset(context);
    final cardWidth = HomeCardLayout.smallCardWidth(context);
    final cardHeight = HomeCardLayout.smallCardHeight(context);
    final showVipBadge = drama.videoAccessType == 1;

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
              authState: authState,
              memberState: memberState,
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
