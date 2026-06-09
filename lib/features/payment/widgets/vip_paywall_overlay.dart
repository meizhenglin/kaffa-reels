import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// ============================================================================
/// VIP 付费墙覆盖层组件
///
/// 【功能说明】
/// 当非VIP用户尝试访问VIP内容时显示的提示层：
/// - 半透明黑色遮罩
/// - 显示锁定图标和VIP提示
/// - 订阅按钮跳转到会员页
/// - 显示VIP权益列表
///
/// 【使用场景】
/// - 播放VIP专属短剧前显示
/// - 访问VIP专区的某些功能时显示
///
/// 【组成部分】
/// - 锁定图标 + 标题
/// - 订阅提示文字
/// - 订阅按钮
/// - VIP权益标签（无广告、高清、下载）
/// - 试用价格提示
///
/// 【如何修改】
/// - 修改标题：修改 title 参数或默认文字
/// - 修改提示文字：修改 build 方法中的字符串
/// - 修改权益列表：修改 _BenefitChip 的使用
/// - 修改按钮颜色：修改 backgroundColor
/// ============================================================================
class VipPaywallOverlay extends StatelessWidget {
  const VipPaywallOverlay({
    super.key,
    this.title,
    this.onUnlock,
    this.canClose = true,
  });

  /// 标题文字（可选，默认 "VIP Content"）
  final String? title;
  /// 解锁按钮点击回调
  final VoidCallback? onUnlock;
  /// 是否显示关闭按钮
  final bool canClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: Colors.black.withAlpha(230),
      child: SafeArea(
        child: Column(
          children: [
            // 关闭按钮（可选）
            if (canClose)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

            const Spacer(),

            // 锁定图标
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(51),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock,
                size: 64,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 24),

            // 标题
            Text(
              title ?? 'VIP Content',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // 提示文字
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Subscribe to VIP to enjoy full access',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),

            // 订阅按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onUnlock?.call();
                  },
                  icon: const Icon(Icons.workspace_premium),
                  label: Text(AppLocalizations.of(context).vipSubscribeNow),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // VIP权益标签
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _BenefitChip(icon: Icons.block, label: 'No Ads'),
                  const SizedBox(width: 12),
                  _BenefitChip(icon: Icons.hd, label: 'HD Quality'),
                  const SizedBox(width: 12),
                  _BenefitChip(icon: Icons.download, label: 'Download'),
                ],
              ),
            ),

            const Spacer(),

            // 试用价格提示
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'First month just \$4.99',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white54,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================================
/// VIP权益标签组件（私有）
///
/// 【功能说明】
/// 显示单个VIP权益的小标签：
/// - 图标 + 文字
/// - 半透明背景
/// - 圆角矩形样式
/// ============================================================================
class _BenefitChip extends StatelessWidget {
  const _BenefitChip({
    required this.icon,
    required this.label,
  });

  /// 图标
  final IconData icon;
  /// 标签文字
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
