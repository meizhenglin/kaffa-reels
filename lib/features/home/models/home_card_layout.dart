import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class HomeCardLayout {
  HomeCardLayout._();

  static const double designWidth = 375;
  static const double minScale = 0.9;
  static const double maxScale = 1.4;
  static const double smallCardTitleAreaHeight = 28;
  static const double bannerHeight = 540;
  static const double smallCardAspectRatio = 150 / 106;
  static const double splashAspectRatio = 812 / 375;
  static const double webMaxWidth = 1024;

  static double _effectiveWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (kIsWeb && w > webMaxWidth) return webMaxWidth;
    return w;
  }

  static double scale(BuildContext context) {
    return (_effectiveWidth(context) / designWidth).clamp(minScale, maxScale);
  }

  static double scaled(BuildContext context, double value) {
    return value * scale(context);
  }

  static double screenWidth(BuildContext context) => _effectiveWidth(context);
  static double screenHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  /// 把算出来的尺寸收敛到 `>= 0`。
  ///
  /// 【为什么需要】浏览器窗口 / iframe 被拖拽缩放时，`MediaQuery.size.width`
  /// 会短暂接近 0（DevTools 设备工具栏、拖动窗口边缘、页面被隐藏都会）。
  /// 此时 `(width - padding*2 - gap*2) / 3` 这类减法会算出负数，
  /// 传给 `SizedBox(width:)` 就变成 `BoxConstraints(w=-17.7)`，
  /// 触发 "BoxConstraints has a negative minimum width." 并直接炸掉整棵元素树
  /// （后面跟着的 "Each child must be laid out exactly once." 都是它的连锁反应）。
  static double _nonNegative(double value) =>
      value.isFinite && value > 0 ? value : 0;

  static double smallCardWidth(BuildContext context) {
    final effectiveWidth = _effectiveWidth(context);
    final horizontalPadding = gridPadding(context);
    final totalGap = cardGap(context) * 2;
    return _nonNegative(
      (effectiveWidth - horizontalPadding * 2 - totalGap) / 3,
    );
  }

  static double smallCardHeight(BuildContext context) =>
      smallCardWidth(context) * smallCardAspectRatio;
  static double smallCardRadius(BuildContext context) => scaled(context, 16);
  static double smallCardTotalHeight(BuildContext context) =>
      smallCardHeight(context) + scaled(context, smallCardTitleAreaHeight);
  static double largeCardRadius(BuildContext context) => scaled(context, 12);
  static double sectionHorizontalPadding(BuildContext context) =>
      scaled(context, 14);
  static double cardGap(BuildContext context) => scaled(context, 15);
  static double gridPadding(BuildContext context) => scaled(context, 15);
  static double bannerScaled(BuildContext context, double value) =>
      scaled(context, value);

  static double largeCardWidth(BuildContext context) {
    final effectiveWidth = _effectiveWidth(context);
    final horizontalPadding = sectionHorizontalPadding(context);
    final gap = cardGap(context);
    return _nonNegative((effectiveWidth - horizontalPadding * 2 - gap) / 2);
  }

  static double largeCardHeight(BuildContext context) {
    final width = largeCardWidth(context);
    return width * 224 / 165;
  }

  static double splashWidth(BuildContext context) => screenWidth(context);
  static double splashHeight(BuildContext context) =>
      splashWidth(context) * splashAspectRatio;
}
