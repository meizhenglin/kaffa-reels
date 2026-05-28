import 'package:flutter/material.dart';

/// ============================================================================
/// RTL 感知图标组件
///
/// 【功能说明】
/// 根据当前文字方向自动翻转的图标组件：
/// - 在 RTL 语言（如阿拉伯语）下水平翻转图标
/// - 适用于需要保持语义方向的图标（如箭头）
///
/// 【使用场景】
/// - 导航箭头图标（前进/后退）
/// - 播放控制图标（快进/快退）
/// - 列表方向图标
///
/// 【原理说明】
/// - 阿拉伯语是从右到左阅读的语言
/// - 某些图标在 RTL 下需要翻转以保持正确的视觉语义
/// - 例如：返回箭头在 RTL 下应该指向右边
///
/// 【参数说明】
/// - icon: 图标数据
/// - size: 图标大小
/// - color: 图标颜色
/// - flipInRtl: 是否在 RTL 模式下翻转
/// - isActive: 是否处于激活状态
///
/// 【如何修改】
/// - 启用/禁用 RTL 翻转：设置 flipInRtl 参数
/// - 修改翻转方向：修改 Transform.scale 的 scaleX 值
/// ============================================================================
class RtlAwareIcon extends StatelessWidget {
  const RtlAwareIcon({
    super.key,
    required this.icon,
    this.size,
    this.color,
    this.flipInRtl = false,
    this.isActive = false,
  });

  /// 图标数据
  final IconData icon;
  /// 图标大小
  final double? size;
  /// 图标颜色
  final Color? color;
  /// 是否在 RTL 模式下翻转
  final bool flipInRtl;
  /// 是否处于激活状态
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    Widget child = Icon(
      icon,
      size: size,
      color: color,
      semanticLabel: '',
    );

    // 在 RTL 模式下水平翻转
    if (flipInRtl && isRtl) {
      child = Transform.scale(
        scaleX: -1,  // 水平翻转
        alignment: Alignment.center,
        child: child,
      );
    }

    return child;
  }
}
