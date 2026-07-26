import 'package:flutter/foundation.dart';

/// AdMob 广告配置
class AdConfig {
  AdConfig._();

  /// 是否启用广告（调试时可关闭）
  static bool get isAdEnabled => kDebugMode ? true : true;

  /// 插屏广告单元 ID
  static String get interstitialAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'ca-app-pub-3738458657290827/9060380177';
    } else {
      return 'ca-app-pub-3738458657290827/9060380177';
    }
  }

  /// 广告加载超时时间（秒）
  static const int adLoadTimeoutSeconds = 10;

  /// 两次插屏广告之间的最小间隔（秒）
  /// 防止广告展示过于频繁
  static const int minIntervalSeconds = 60;
}
