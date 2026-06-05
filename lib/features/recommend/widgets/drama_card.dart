import 'package:flutter/material.dart';

import '../../home/models/home_card_layout.dart';
import '../../../components/preload_network_image.dart';
import '../models/drama.dart';
import '../models/drama_badge.dart';

/// ============================================================================
/// 短剧卡片组件（横屏版）
///
/// 【功能说明】
/// 显示单个短剧的卡片（横向布局）：
/// - 封面图片（带标签和播放量）
/// - 评分和集数
/// - 标题和简介
///
/// 【使用场景】
/// - 首页热门推荐的横向滚动列表
/// - 推荐页的横向滚动列表
///
/// 【组成部分】
/// - 封面图片区域（Stack 布局）
///   - 封面图
///   - 标签（热、新、VIP等）
///   - VIP徽章
///   - 播放量
/// - 信息区域
///   - 评分 + 集数
///   - 标题
///   - 简介（可选）
///
/// 【如何修改】
/// - 修改卡片宽度：修改 width 参数（默认 140）
/// - 修改封面比例：修改 drama.aspectRatio
/// - 修改标签样式：修改 _BadgeChip 组件
/// ============================================================================
class DramaCard extends StatelessWidget {
  const DramaCard({
    super.key,
    required this.drama,
    this.onTap,
    this.width,
    this.showDescription = false,
  });

  /// 短剧数据
  final Drama drama;
  /// 点击回调
  final VoidCallback? onTap;
  /// 卡片宽度（默认 140）
  final double? width;
  /// 是否显示简介
  final bool showDescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final cardWidth = width ?? HomeCardLayout.bannerScaled(context, 140);
    final cardRadius = HomeCardLayout.bannerScaled(context, 12);
    final edgeInset = HomeCardLayout.bannerScaled(context, 8);
    final titleSpacing = HomeCardLayout.bannerScaled(context, 8);
    final compactSpacing = HomeCardLayout.bannerScaled(context, 4);
    final starSize = HomeCardLayout.bannerScaled(context, 16);

    return SizedBox(
      width: cardWidth,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== 封面图片区域 ==========
            Stack(
              children: [
                // 封面图片
                ClipRRect(
                  borderRadius: BorderRadius.circular(cardRadius),
                  child: AspectRatio(
                    aspectRatio: drama.aspectRatio,
                    child: _CoverImage(url: drama.coverUrl),
                  ),
                ),
                // 标签
                if (drama.badge != null)
                  PositionedDirectional(
                    top: edgeInset,
                    end: edgeInset,
                    child: _BadgeChip(
                      badge: drama.badge!,
                      isArabic: isArabic,
                    ),
                  ),
                // VIP徽章
                if (drama.isVipOnly)
                  PositionedDirectional(
                    top: edgeInset,
                    start: edgeInset,
                    child: _VipBadge(size: HomeCardLayout.bannerScaled(context, 10)),
                  ),
                // 播放量
                PositionedDirectional(
                  start: edgeInset,
                  bottom: edgeInset,
                  child: _ViewsChip(views: drama.formattedViews),
                ),
              ],
            ),
            SizedBox(height: titleSpacing),

            // ========== 评分和集数 ==========
            Row(
              children: [
                Icon(
                  Icons.star_rounded,
                  size: starSize,
                  color: Colors.amber.shade600,
                ),
                SizedBox(width: compactSpacing),
                Text(
                  drama.rating.toStringAsFixed(1),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${drama.episodeCount} EP',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            SizedBox(height: compactSpacing),

            // ========== 标题 ==========
            Text(
              drama.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),

            // ========== 简介（可选）==========
            if (showDescription) ...[
              SizedBox(height: compactSpacing),
              Text(
                drama.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ============================================================================
/// 短剧网格卡片组件
///
/// 【功能说明】
/// 宽度自适应的短剧卡片：
/// - 继承 DramaCard 的样式
/// - 宽度占满可用空间
///
/// 【使用场景】
/// - 瀑布流布局中的短剧卡片
/// ============================================================================
class DramaGridCard extends StatelessWidget {
  const DramaGridCard({
    super.key,
    required this.drama,
    this.onTap,
  });

  /// 短剧数据
  final Drama drama;
  /// 点击回调
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DramaCard(
      drama: drama,
      onTap: onTap,
      width: double.infinity,  // 占满宽度
    );
  }
}

/// ============================================================================
/// 封面图片组件（私有）
///
/// 【功能说明】
/// 加载并显示短剧封面图片：
/// - 支持网络图片
/// - 加载中显示进度指示器
/// - 加载失败显示占位图
/// ============================================================================
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url});

  /// 图片URL
  final String url;

  @override
  Widget build(BuildContext context) {
    return PreloadNetworkImage(
      imageUrl: url,
      preloadAsset: 'assets/images/small_preload_bg.png',
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
    );
  }
}

/// ============================================================================
/// 标签芯片组件（私有）
///
/// 【功能说明】
/// 显示短剧标签（热、新、VIP等）：
/// - 彩色背景
/// - 白色文字
/// - 小圆角矩形
///
/// 【标签类型】
/// - hot: 红色，HOT
/// - newDrama: 蓝色，NEW
/// - vip: 金色，VIP
/// - update: 绿色，UPDATE
/// - exclusive: 紫色，EXCLUSIVE
/// ============================================================================
class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge, required this.isArabic});

  /// 标签类型
  final DramaBadge badge;
  /// 是否为阿拉伯语
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = HomeCardLayout.bannerScaled(context, 8);
    final verticalPadding = HomeCardLayout.bannerScaled(context, 4);
    final radius = HomeCardLayout.bannerScaled(context, 6);
    final fontSize = HomeCardLayout.bannerScaled(context, 10);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: badge.color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        badge.label(isArabic),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// ============================================================================
/// VIP徽章组件（私有）
///
/// 【功能说明】
/// 显示VIP专属标识：
/// - 半透明黑色背景
/// - 金色"VIP"文字
/// ============================================================================
class _VipBadge extends StatelessWidget {
  const _VipBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = size * 0.6;
    final verticalPadding = size * 0.3;
    final radius = size * 0.6;
    final fontSize = size;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        'VIP',
        style: TextStyle(
          color: const Color(0xFFFFD700),
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// ============================================================================
/// 播放量组件（私有）
///
/// 【功能说明】
/// 显示短剧播放量：
/// - 播放图标 + 数字
/// - 半透明黑色背景
/// - 白色文字
/// ============================================================================
class _ViewsChip extends StatelessWidget {
  const _ViewsChip({required this.views});

  /// 格式化后的播放量（如 "1.2M"）
  final String views;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = HomeCardLayout.bannerScaled(context, 8);
    final verticalPadding = HomeCardLayout.bannerScaled(context, 4);
    final radius = HomeCardLayout.bannerScaled(context, 6);
    final iconSize = HomeCardLayout.bannerScaled(context, 14);
    final gap = HomeCardLayout.bannerScaled(context, 2);
    final fontSize = HomeCardLayout.bannerScaled(context, 11);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, color: Colors.white, size: iconSize),
          SizedBox(width: gap),
          Text(
            views,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
