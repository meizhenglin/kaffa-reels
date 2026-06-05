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

  static double scale(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return (screenWidth / designWidth).clamp(minScale, maxScale);
  }

  static double scaled(BuildContext context, double value) {
    return value * scale(context);
  }

  static double screenWidth(BuildContext context) => MediaQuery.of(context).size.width;
  static double screenHeight(BuildContext context) => MediaQuery.of(context).size.height;

  static double smallCardWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = gridPadding(context);
    final totalGap = cardGap(context) * 2;
    return (screenWidth - horizontalPadding * 2 - totalGap) / 3;
  }

  static double smallCardHeight(BuildContext context) =>
      smallCardWidth(context) * smallCardAspectRatio;
  static double smallCardRadius(BuildContext context) => scaled(context, 16);
  static double smallCardTotalHeight(BuildContext context) =>
      smallCardHeight(context) + scaled(context, smallCardTitleAreaHeight);
  static double largeCardRadius(BuildContext context) => scaled(context, 12);
  static double sectionHorizontalPadding(BuildContext context) => scaled(context, 14);
  static double cardGap(BuildContext context) => scaled(context, 15);
  static double gridPadding(BuildContext context) => scaled(context, 15);
  static double bannerScaled(BuildContext context, double value) =>
      scaled(context, value);

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

  static double splashWidth(BuildContext context) => screenWidth(context);
  static double splashHeight(BuildContext context) =>
      splashWidth(context) * splashAspectRatio;
}
