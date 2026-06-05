import 'package:flutter/material.dart';

class HomeCardLayout {
  HomeCardLayout._();

  static const double designWidth = 375;
  static const double minScale = 0.9;
  static const double maxScale = 1.15;

  static double scale(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return (screenWidth / designWidth).clamp(minScale, maxScale);
  }

  static double scaled(BuildContext context, double value) {
    return value * scale(context);
  }

  static double smallCardWidth(BuildContext context) => scaled(context, 106);
  static double smallCardHeight(BuildContext context) => scaled(context, 150);
  static double smallCardRadius(BuildContext context) => scaled(context, 16);
  static double largeCardRadius(BuildContext context) => scaled(context, 12);
  static double sectionHorizontalPadding(BuildContext context) => scaled(context, 14);
  static double cardGap(BuildContext context) => scaled(context, 15);
  static double gridPadding(BuildContext context) => scaled(context, 15);

  static double largeCardWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = sectionHorizontalPadding(context);
    final gap = cardGap(context);
    return (screenWidth - horizontalPadding * 2 - gap) / 2;
  }

  static double largeCardHeight(BuildContext context) {
    final width = largeCardWidth(context);
    return width * 224 / 165;
  }
}
