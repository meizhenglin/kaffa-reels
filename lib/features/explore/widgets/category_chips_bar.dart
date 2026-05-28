import 'package:flutter/material.dart';

import '../models/category.dart';

/// ============================================================================
/// 分类标签栏组件
///
/// 【功能说明】
/// 显示横向滚动的分类标签：
/// - 水平滚动的分类列表
/// - 选中项有下划线指示器
/// - 选中项文字变为主题色加粗
/// - 根据语言显示对应的分类名称
///
/// 【使用场景】
/// - ExplorePage（探索页）顶部的分类筛选栏
///
/// 【样式特点】
/// - 标签等间距排列
/// - 选中标签下方有彩色下划线
/// - 选中/未选中状态文字颜色不同
///
/// 【参数说明】
/// - categories: 分类列表
/// - selectedId: 当前选中的分类ID
/// - onSelected: 选中分类的回调
///
/// 【如何修改】
/// - 修改标签间距：修改 ListView.separated 的 separatorBuilder
/// - 修改下划线颜色：修改 AnimatedContainer 的 color
/// - 修改选中/未选中颜色：修改 Text 的 style
/// ============================================================================
class CategoryChipsBar extends StatelessWidget {
  const CategoryChipsBar({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  /// 分类列表
  final List<Category> categories;
  /// 当前选中的分类ID
  final String selectedId;
  /// 选中分类的回调
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final theme = Theme.of(context);

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,  // 水平滚动
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),  // 标签间距
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category.id == selectedId;

          return GestureDetector(
            onTap: () => onSelected(category.id),
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 分类名称
                Text(
                  category.localizedName(locale),  // 根据语言返回对应名称
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? theme.colorScheme.primary  // 选中：主题色
                        : theme.colorScheme.onSurface.withValues(alpha: 0.65),  // 未选中：灰色
                  ),
                ),
                const SizedBox(height: 6),
                // 下划线指示器
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),  // 动画时长
                  height: 3,
                  width: isSelected ? 24 : 0,  // 选中时显示，未选中时隐藏
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
