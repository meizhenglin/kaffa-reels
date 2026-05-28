import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// ============================================================================
/// Tab 占位页组件
///
/// 【功能说明】
/// 当某个 Tab 页面还在开发中时显示的占位页面：
/// - 显示 Tab 名称和大图标
/// - 提示"开发中"或"即将上线"
/// - 包含建设中的提示信息
///
/// 【使用场景】
/// - 某些尚未实现具体功能的 Tab 页面
/// - 开发阶段临时使用的占位页面
///
/// 【如何修改】
/// - 修改占位图标：在 build 方法中修改 Icon 的 icon 属性
/// - 修改显示文字：修改 l10n.underDevelopment 和 l10n.comingSoon
/// - 修改卡片内容：修改 Card 内的文本
/// ============================================================================
class PlaceholderTabPage extends StatelessWidget {
  const PlaceholderTabPage({
    super.key,
    required this.tabId,
    required this.title,
    required this.icon,
    this.scrollController,
  });

  /// Tab 唯一标识符
  final String tabId;
  /// 显示的标题
  final String title;
  /// 显示的大图标
  final IconData icon;
  /// 滚动控制器（可选）
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          // 大图标
          Icon(
            icon,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 24),
          // 标题
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // "开发中" 提示
          Text(
            l10n.underDevelopment,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          // "即将上线" 提示
          Text(
            l10n.comingSoon,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 48),
          // 提示卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    Icons.construction_outlined,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      l10n.comingSoon,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
