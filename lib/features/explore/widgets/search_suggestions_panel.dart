import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../models/search_suggestion.dart';
import '../providers/search_provider.dart';

/// ============================================================================
/// 搜索建议面板组件
///
/// 【功能说明】
/// 显示搜索建议的下拉面板：
/// - 最近搜索历史
/// - 热门搜索词
/// - 支持删除单条历史记录
/// - 支持清空所有历史
///
/// 【使用场景】
/// - ExplorePage（探索页）搜索框获得焦点时显示
///
/// 【组成部分】
/// - _SectionLabel: 分类标签（"最近搜索" / "热门搜索"）
/// - _SuggestionTile: 单条建议项
///
/// 【数据来源】
/// - 从 searchProvider 获取建议列表
/// - SearchSuggestionType.recent: 最近搜索
/// - SearchSuggestionType.hot: 热门搜索
///
/// 【如何修改】
/// - 修改面板高度：通过 Material 的 elevation 调整阴影
/// - 修改圆角：修改 borderRadius
/// - 修改列表项样式：修改 ListTile 属性
/// ============================================================================
class SearchSuggestionsPanel extends ConsumerWidget {
  const SearchSuggestionsPanel({
    super.key,
    required this.onSuggestionTap,
  });

  /// 建议项点击回调
  final void Function(String keyword) onSuggestionTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final search = ref.watch(searchProvider);
    // 过滤出最近搜索
    final recent = search.suggestions
        .where((s) => s.type == SearchSuggestionType.recent)
        .toList();
    // 过滤出热门搜索
    final hot = search.suggestions
        .where((s) => s.type == SearchSuggestionType.hot)
        .toList();

    return Material(
      elevation: 4,  // 阴影高度
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        shrinkWrap: true,  // 收缩内容
        children: [
          // 最近搜索部分
          if (recent.isNotEmpty) ...[
            _SectionLabel(
              title: l10n.search,  // "搜索"
              trailing: TextButton(
                onPressed: () => ref.read(searchProvider.notifier).clearHistory(),
                child: Text(l10n.delete),
              ),
            ),
            ...recent.map(
              (s) => _SuggestionTile(
                suggestion: s,
                onTap: () => onSuggestionTap(s.keyword),
                onDelete: () =>
                    ref.read(searchProvider.notifier).removeHistoryItem(s.keyword),
              ),
            ),
          ],
          // 热门搜索部分
          if (hot.isNotEmpty) ...[
            _SectionLabel(title: l10n.trending),
            ...hot.map(
              (s) => _SuggestionTile(
                suggestion: s,
                onTap: () => onSuggestionTap(s.keyword),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ============================================================================
/// 分类标签组件（私有）
///
/// 【功能说明】
/// 显示建议面板中的分类标题：
/// - 左侧显示标题
/// - 右侧可选显示操作按钮（如"清空"）
/// ============================================================================
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.trailing});

  /// 标题文字
  final String title;
  /// 右侧操作组件（可选）
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const Spacer(),
          trailing ?? const SizedBox.shrink(),  // 如果没有 trailing，显示空白
        ],
      ),
    );
  }
}

/// ============================================================================
/// 建议项组件（私有）
///
/// 【功能说明】
/// 显示单条搜索建议：
/// - 左侧显示图标（历史/热门）
/// - 中间显示关键词
/// - 右侧可选显示删除按钮
/// ============================================================================
class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.onTap,
    this.onDelete,
  });

  /// 建议数据
  final SearchSuggestion suggestion;
  /// 点击回调
  final VoidCallback onTap;
  /// 删除回调（仅最近搜索有）
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isRecent = suggestion.type == SearchSuggestionType.recent;

    return ListTile(
      dense: true,  // 紧凑样式
      leading: Icon(
        isRecent ? Icons.history : Icons.local_fire_department_outlined,  // 历史图标 / 热门图标
        size: 20,
        color: isRecent
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(suggestion.keyword),
      trailing: isRecent && onDelete != null
          ? IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDelete,
            )
          : null,
      onTap: onTap,
    );
  }
}
