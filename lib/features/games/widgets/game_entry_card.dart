import 'package:flutter/material.dart';

/// ============================================================================
/// 游戏入口卡片组件
///
/// 【功能说明】
/// 显示游戏中心单个游戏的入口卡片：
/// - 大图标 + 标题 + 描述
/// - 可选显示最高分/最佳记录
/// - 点击进入游戏
///
/// 【使用场景】
/// - GamesPage（游戏中心页）的游戏列表
///
/// 【样式特点】
/// - 渐变色图标背景
/// - 卡片阴影效果
/// - 最高分显示在底部
///
/// 【组成部分】
/// - 渐变背景的图标容器
/// - 游戏标题
/// - 游戏描述
/// - 最高分标签（可选）
///
/// 【如何修改】
/// - 修改图标大小：修改 Container 的 width/height
/// - 修改卡片间距：修改 Padding 和 SizedBox
/// - 修改渐变色：修改 LinearGradient 的 colors
/// - 修改分数样式：修改 Container 的背景色和圆角
/// ============================================================================
class GameEntryCard extends StatelessWidget {
  const GameEntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.highScore,
    this.onTap,
  });

  /// 游戏图标
  final IconData icon;
  /// 游戏标题
  final String title;
  /// 游戏描述
  final String description;
  /// 最高分/最佳记录（可选）
  final String? highScore;
  /// 点击回调
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,  // 阴影高度
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 渐变图标容器
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.secondaryContainer,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),

              // 游戏标题
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // 游戏描述
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // 最高分标签（如果有）
              if (highScore != null && highScore!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.emoji_events,  // 奖杯图标
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        highScore!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
