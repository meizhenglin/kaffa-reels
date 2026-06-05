import 'package:flutter/material.dart';

import '../../../components/preload_network_image.dart';
import '../../../core/utils/localized_badge_assets.dart';
import '../../home/models/home_card_layout.dart';
import '../../recommend/models/drama.dart';

class ExploreDramaGridCard extends StatelessWidget {
  const ExploreDramaGridCard({
    super.key,
    required this.drama,
    this.onTap,
  });

  final Drama drama;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vipBadgeAsset = localizedHomeVipBadgeAsset(context);
    final cardHeight = HomeCardLayout.smallCardHeight(context);
    final cardRadius = HomeCardLayout.smallCardRadius(context);
    final titleSpacing = HomeCardLayout.scaled(context, 5);
    final vipBadgeWidth = HomeCardLayout.scaled(context, 42);
    final vipBadgeHeight = HomeCardLayout.scaled(context, 18);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: cardHeight,
            width: double.infinity,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(cardRadius),
                  child: PreloadNetworkImage(
                    imageUrl: drama.coverUrl,
                    preloadAsset: 'assets/images/small_preload_bg.png',
                    fit: BoxFit.cover,
                  ),
                ),
                if (drama.videoAccessType == 1)
                  PositionedDirectional(
                    top: 0,
                    start: 0,
                    child: Image.asset(
                      vipBadgeAsset,
                      width: vipBadgeWidth,
                      height: vipBadgeHeight,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: titleSpacing),
          Text(
            drama.title.split(' / ').first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontSize: HomeCardLayout.scaled(context, 13),
                ),
          ),
        ],
      ),
    );
  }
}
