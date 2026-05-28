import 'package:flutter/material.dart';

import '../../recommend/models/drama.dart';
import '../../recommend/models/drama_badge.dart';
import 'highlighted_text.dart';

/// ============================================================================
/// 探索页短剧网格卡片组件
///
/// 【功能说明】
/// 探索页使用的紧凑型短剧卡片（3列网格布局）：
/// - 封面图片（带标签和播放量）
/// - 评分和标题
/// - 支持搜索关键词高亮
///
/// 【使用场景】
/// - ExplorePage（探索页）的短剧网格
///
/// 【组成部分】
/// - 封面图片区域（Stack 布局）
///   - 封面图
///   - 标签（热、新等）
///   - 播放量
/// - 信息区域
///   - 评分
///   - 标题（支持高亮）
///
/// 【样式特点】
/// - 相比 DramaCard 更紧凑
/// - 适合多列网格展示
/// - 无简介显示
///
/// 【如何修改】
/// - 修改封面比例：修改 AspectRatio 的 aspectRatio（当前 0.72）
/// - 修改标签大小：修改 Container 的 padding
/// - 修改卡片间距：在父组件中调整
/// ============================================================================
class ExploreDramaGridCard extends StatelessWidget {
  const ExploreDramaGridCard({
    super.key,
    required this.drama,
    this.onTap,
    this.highlightQuery,
  });

  /// 短剧数据
  final Drama drama;
  /// 点击回调
  final VoidCallback? onTap;
  /// 搜索关键词（用于高亮显示）
  final String? highlightQuery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ========== 封面图片区域 ==========
          AspectRatio(
            aspectRatio: 0.72,  // 宽高比
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 封面图片
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    drama.coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.broken_image_outlined, size: 24),
                    ),
                  ),
                ),

                // 标签
                if (drama.badge != null)
                  PositionedDirectional(
                    top: 6,
                    end: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: drama.badge!.color,  // 使用扩展的颜色
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        drama.badge!.label(isArabic),  // 使用扩展的方法
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // 播放量
                PositionedDirectional(
                  start: 6,
                  bottom: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                      Text(
                        drama.formattedViews,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // ========== 评分 ==========
          Row(
            children: [
              Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade600),
              const SizedBox(width: 2),
              Text(
                drama.rating.toStringAsFixed(1),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),

          // ========== 标题（支持高亮）==========
          highlightQuery != null && highlightQuery!.isNotEmpty
              ? HighlightedText(
                  text: drama.title,
                  highlight: highlightQuery!,
                  maxLines: 2,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                )
              : Text(
                  drama.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
        ],
      ),
    );
  }
}
