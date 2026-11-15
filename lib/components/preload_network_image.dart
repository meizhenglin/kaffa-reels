import 'package:flutter/material.dart';

class PreloadNetworkImage extends StatelessWidget {
  const PreloadNetworkImage({
    super.key,
    required this.imageUrl,
    required this.preloadAsset,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.cacheWidth,
    this.cacheHeight,
  });

  final String imageUrl;
  final String preloadAsset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Duration fadeInDuration;

  /// 解码像素宽度。不传时按 [width] × 设备像素比自动估算。
  ///
  /// 【为什么要降采样】服务端封面图普遍是 800~1200px 宽的原图，而列表卡片
  /// 实际只显示 ~110 逻辑像素。不传 cacheWidth 时 Flutter 会按原图分辨率
  /// 完整解码进内存缓存，列表滚动时内存峰值高、GC 压力大、容易掉帧。
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    final borderRadius = this.borderRadius;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    // 显示宽度 × dpr = 需要的物理像素。
    // ⚠️ 只约束宽度：cacheWidth 和 cacheHeight 同时设置时，ResizeImage 会把
    // 原图强行拉伸到目标尺寸（不保持宽高比），封面图会变形。只给宽度时
    // 解码器按比例缩放，纵向裁切交给 BoxFit.cover。
    // 调用方显式传入的 cacheWidth 也要防脏值（0 / 负数会让解码器报错）
    final effectiveCacheWidth = (cacheWidth != null && cacheWidth! > 0)
        ? cacheWidth
        : _estimateCacheSize(width, dpr);

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: SizedBox(
        width: width ?? double.infinity,
        height: height ?? double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(preloadAsset, width: double.infinity, height: double.infinity, fit: fit),
            Image.network(
              imageUrl,
              width: double.infinity,
              height: double.infinity,
              fit: fit,
              cacheWidth: effectiveCacheWidth,
              cacheHeight: cacheHeight,
              // URL 变化（换封面）时不闪烁，继续显示上一帧直到新帧就绪
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                // 【修复 fade-in】原来的写法是
                //   AnimatedOpacity(opacity: 1, ...)
                // 恒为 1，动画从未生效。正确做法：frame == null（首帧还没
                // 解码好）时透明度 0，解码完成后 Tween 到 1。
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: fadeInDuration,
                  curve: Curves.easeOut,
                  child: child,
                );
              },
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// 按显示宽度估算解码宽度：逻辑像素 × dpr。
  ///
  /// 返回 null 表示「不做降采样」（保持原图分辨率），触发条件：
  /// - [logicalSize] 为 null —— 调用方没指定宽度，实际由父布局决定；
  /// - 非有限值 —— 大量调用方传的是 `width: double.infinity`
  ///   （banner / 卡片铺满父容器）。**这里必须拦**：对 infinity 调
  ///   `.round()` 会直接抛 `Unsupported operation: Infinity or NaN toInt`，
  ///   表现就是整块封面变红屏；
  /// - <= 0 —— 布局还没测量出来（约束为 0）时不做任何假设。
  ///
  /// 上限 2048 兜住超大屏 / 异常 dpr，避免一次解码吃掉几十 MB。
  static int? _estimateCacheSize(double? logicalSize, double dpr) {
    if (logicalSize == null) return null;
    if (!logicalSize.isFinite || logicalSize <= 0) return null;
    if (!dpr.isFinite || dpr <= 0) return null;
    final target = logicalSize * dpr;
    if (!target.isFinite) return null;
    return target.round().clamp(1, 2048);
  }
}
