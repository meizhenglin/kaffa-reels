import 'package:flutter/foundation.dart';

/// AdMob 广告配置
class AdConfig {
  AdConfig._();

  /// 是否启用广告（调试时可关闭）
  static bool get isAdEnabled => kDebugMode ? true : true;

  /// 是否启用 AdMob 广告（测试 Meta 时可关闭）
  static bool get isAdmobEnabled => kDebugMode ? false : true;

  /// AdMob 插屏广告单元 ID
  static String get interstitialAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'ca-app-pub-3738458657290827/9060380177';
    } else {
      return 'ca-app-pub-3738458657290827/9060380177';
    }
  }

  /// AdMob 激励广告单元 ID
  static String get admobRewardedAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'ca-app-pub-3738458657290827/6345591075';
    } else {
      return 'ca-app-pub-3738458657290827/6345591075';
    }
  }

  /// 激励广告 Placement ID（使用插屏广告，因为激励广告仅限游戏应用）
  static String get metaRewardedAdPlacementId {
    // 使用插屏版位 ID，因为 Meta 激励广告仅限游戏类应用
    if (defaultTargetPlatform == TargetPlatform.android) {
      return '1362862869311950_1362862935978610'; // 使用插屏版位
    } else {
      return '1362862869311950_1362862935978610'; // 使用插屏版位
    }
  }

  /// Meta 插屏广告 Placement ID
  static String get metaInterstitialAdPlacementId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return '1362862869311950_1362862935978610';
    } else {
      return '1362862869311950_1362862935978610';
    }
  }

  /// 广告加载超时时间（秒）
  static const int adLoadTimeoutSeconds = 10;

  /// 两次插屏广告之间的最小间隔（秒）
  /// 防止广告展示过于频繁
  static const int minIntervalSeconds = 60;
}
