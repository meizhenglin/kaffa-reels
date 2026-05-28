import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../models/drama.dart';
import 'drama_card.dart';

/// ============================================================================
/// 热门短剧板块组件
///
/// 【功能说明】
/// 显示热门短剧的横向滚动列表：
/// - 横向滚动的短剧卡片列表
/// - 板块标题和"查看更多"按钮
/// - 使用 DramaCard 组件显示每个短剧
///
/// 【使用场景】
/// - 首页顶部的"热门推荐"板块
/// - 推荐页的热门短剧列表
///
/// 【组成部分】
/// - _SectionHeader: 板块标题栏（标题 + 查看更多按钮）
/// - ListView.separated: 横向滚动的短剧列表
///
/// 【如何修改】
/// - 修改卡片宽度：在 DramaCard 的 width 参数修改（当前 130）
/// - 修改列表高度：在 SizedBox 的 height 参数修改（当前 250）
/// - 修改间距：修改 separatorBuilder 和 itemBuilder 中的 SizedBox
/// - 修改标题文字：修改 l10n.trending 或 l10n.viewAll
/// ============================================================================
class HotDramaSection extends StatelessWidget {
  const HotDramaSection({
    super.key,
    required this.dramas,
    required this.onDramaTap,
    required this.onSeeMore,
  });

  /// 短剧数据列表
  final List<Drama> dramas;
  /// 短剧点击回调
  final void Function(Drama drama) onDramaTap;
  /// 点击"查看更多"的回调
  final VoidCallback onSeeMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 板块标题栏
        _SectionHeader(
          title: l10n.trending,
          onSeeMore: onSeeMore,
        ),
        const SizedBox(height: 12),
        // 横向滚动列表
        SizedBox(
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,  // 水平滚动
            padding: const EdgeInsetsDirectional.only(start: 16, end: 16),
            itemCount: dramas.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),  // 卡片间距
            itemBuilder: (context, index) {
              final drama = dramas[index];
              return DramaCard(
                drama: drama,
                width: 130,  // 卡片宽度
                onTap: () => onDramaTap(drama),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// ============================================================================
/// 板块标题栏组件（私有）
///
/// 【功能说明】
/// 显示板块标题和"查看更多"按钮：
/// - 左侧显示板块标题
/// - 右侧显示"查看更多"按钮（带箭头）
/// - 按钮文字方向根据 RTL/LTR 自动调整
///
/// 【组成部分】
/// - Text: 标题文字
/// - TextButton: 查看更多按钮
/// - Icon: 箭头图标
/// ============================================================================
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.onSeeMore,
  });

  /// 板块标题
  final String title;
  /// 点击回调
  final VoidCallback onSeeMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      child: Row(
        children: [
          // 标题
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          // 查看更多按钮
          TextButton(
            onPressed: onSeeMore,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.viewAll),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,  // 右箭头图标
                  size: 20,
                  textDirection: Directionality.of(context),  // 根据语言方向调整
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
