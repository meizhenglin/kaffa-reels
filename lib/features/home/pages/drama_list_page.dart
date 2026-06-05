import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../components/preload_network_image.dart';
import '../../../components/rtl_back_button.dart';
import '../../../core/utils/localized_badge_assets.dart';
import '../../../l10n/app_localizations.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';
import '../../recommend/models/drama.dart';
import '../../recommend/models/drama_list_type.dart';
import '../../recommend/providers/recommend_provider.dart';
import '../../recommend/utils/drama_navigation.dart';

/// 短剧列表页面
///
/// 支持展示热门短剧列表和全部推荐列表，通过 [DramaListType] 区分
class DramaListPage extends ConsumerWidget {
  const DramaListPage({
    super.key,
    required this.type,
  });

  final DramaListType type;

  String _title(AppLocalizations l10n) {
    switch (type) {
      case DramaListType.hot:
        return l10n.topRecommend;
      case DramaListType.recommended:
        return l10n.allRecommended;
    }
  }

  List<Drama> _dramas(RecommendState state) {
    switch (type) {
      case DramaListType.hot:
        return state.hotPicks;
      case DramaListType.recommended:
        return state.newEpisodes;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              child: _buildBody(context, ref, dramas, isLoading),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<Drama> dramas,
    bool isLoading,
  ) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (dramas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.movie_outlined,
              size: 64,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            Text(
              'No dramas available',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white60,
                  ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(15),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 15,
        crossAxisSpacing: 15,
        childAspectRatio: 106 / 165,
      ),
      itemCount: dramas.length,
      itemBuilder: (context, index) {
        final drama = dramas[index];
        return _buildCard(
          context,
          ref,
          index,
          drama,
        );
      },
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

    return SizedBox(
      width: 106,
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
                  borderRadius: BorderRadius.circular(16),
                  child: PreloadNetworkImage(
                    imageUrl: coverUrl,
                    preloadAsset: 'assets/images/small_preload_bg.png',
                    width: 106,
                    height: 150,
                    fit: BoxFit.cover,
                  ),
                ),
                // 前5名角标
                if (index < 5)
                  PositionedDirectional(
                    top: 0,
                    start: 0,
                    child: Image.asset(
                      rankBadgeAsset,
                      width: 22,
                      height: 22,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            drama.title.split(' / ').first,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,fontSize: 13,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
