import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../models/drama.dart';
import 'drama_card.dart';

/// ============================================================================
/// 双列瀑布流布局组件
///
/// 【功能说明】
/// 将短剧以双列瀑布流形式展示：
/// - 自动将短剧分配到左右两列
/// - 根据封面比例计算每列高度，保持两列均衡
/// - 支持"查看更多"按钮
/// - 支持加载更多状态显示
///
/// 【使用场景】
/// - 推荐页的"为你推荐"板块
/// - 瀑布流形式展示短剧列表
///
/// 【布局算法】
/// - 遍历所有短剧
/// - 根据封面比例（aspectRatio）计算每项高度
/// - 将短剧分配到当前高度较小的列
/// - 实现近似均衡的双列瀑布流
///
/// 【如何修改】
/// - 修改列间距：修改 Row 中两个 Expanded 之间的 SizedBox
/// - 修改卡片间距：修改 _WaterfallColumn 中的 const SizedBox(height: 12)
/// - 修改标题文字：修改 l10n.recommended 或 l10n.viewAll
/// ============================================================================
class RecommendWaterfallGrid extends StatelessWidget {
  const RecommendWaterfallGrid({
    super.key,
    required this.dramas,
    required this.onDramaTap,
    required this.onSeeMore,
    this.isLoadingMore = false,
  });

  /// 短剧数据列表
  final List<Drama> dramas;
  /// 短剧点击回调
  final void Function(Drama drama) onDramaTap;
  /// 点击"查看更多"的回调
  final VoidCallback onSeeMore;
  /// 是否正在加载更多
  final bool isLoadingMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final leftColumn = <Drama>[];
    final rightColumn = <Drama>[];
    double leftHeight = 0;
    double rightHeight = 0;

    // 将短剧分配到左右两列
    for (final drama in dramas) {
      final itemHeight = 1 / drama.aspectRatio;  // 根据比例计算高度
      if (leftHeight <= rightHeight) {
        leftColumn.add(drama);
        leftHeight += itemHeight;
      } else {
        rightColumn.add(drama);
        rightHeight += itemHeight;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.recommended,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              TextButton(
                onPressed: onSeeMore,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.viewAll),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 20, textDirection: Directionality.of(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 双列瀑布流
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左列
              Expanded(
                child: _WaterfallColumn(
                  dramas: leftColumn,
                  onDramaTap: onDramaTap,
                ),
              ),
              const SizedBox(width: 12),  // 列间距
              // 右列
              Expanded(
                child: _WaterfallColumn(
                  dramas: rightColumn,
                  onDramaTap: onDramaTap,
                ),
              ),
            ],
          ),
        ),
        // 加载更多指示器
        if (isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

/// ============================================================================
/// 瀑布流单列组件（私有）
///
/// 【功能说明】
/// 显示瀑布流中的一列短剧：
/// - 垂直排列多个 DramaGridCard
/// - 卡片之间有固定间距
///
/// 【使用场景】
/// - RecommendWaterfallGrid 的左右两列
/// ============================================================================
class _WaterfallColumn extends StatelessWidget {
  const _WaterfallColumn({
    required this.dramas,
    required this.onDramaTap,
  });

  /// 该列的短剧列表
  final List<Drama> dramas;
  /// 短剧点击回调
  final void Function(Drama drama) onDramaTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final drama in dramas) ...[
          DramaGridCard(
            drama: drama,
            onTap: () => onDramaTap(drama),
          ),
          const SizedBox(height: 12),  // 卡片间距
        ],
      ],
    );
  }
}
