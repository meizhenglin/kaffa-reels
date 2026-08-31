import 'package:flutter/foundation.dart' show kIsWeb;

/// ============================================================================
/// 应用配置文件
///
/// 【功能说明】
/// 对应小程序原版 config.js，定义 API 地址、平台标识、X-Client 信息等。
///
/// 【如何修改】
/// - 切换环境：修改 _apiBaseUrl
/// - 切换平台：修改当前使用的 X-Client 字符串（Android/iOS）
/// - 版本更新：修改 appVersion
/// ============================================================================
class AppConfig {
  AppConfig._();

  // ==================== API 配置 ====================
  /// 正式环境 API 地址（私有常量）
  // static const String apiBaseUrl = 'https://tvapi.qahwatv.com/';

  // test 环境 API 地址
  // static const String apiBaseUrl ="http://101.46.59.160:8082/";
 
  // 开发环境
  static const String apiBaseUrl = 'http://192.168.1.51:8082/';


  /// 如需切回联调环境，可临时使用：
  /// https://scolding-unbaked-refrain.ngrok-free.dev/
  /// 
  /// https://tvapi.qahwatv.com/
  /// 
  /// 
  /// 
  /// 
  /// # Google Play 版（只有 Google 支付）
  // flutter run --flavor google -t lib/main.dart --dart-define=FLAVOR=google
  // flutter build apk --flavor google -t lib/main.dart --dart-define=FLAVOR=google --release

  // # 自主平台版（只有 HaiPay）
// flutter run --flavor platform -t lib/main.dart --dart-define=FLAVOR=platform
// flutter build apk --flavor platform -t lib/main.dart --dart-define=FLAVOR=platform --release





// 用途	命令
// Platform debug 分包（刚跑）
// flutter build apk --flavor platform -t lib/main.dart --dart-define=FLAVOR=platform --debug --split-per-abi
// Google debug 分包
// flutter build apk --flavor google -t lib/main.dart --dart-define=FLAVOR=google --debug --split-per-abi
// Platform release 分包
// flutter build apk --flavor platform -t lib/main.dart --dart-define=FLAVOR=platform --release --split-per-abi
// Platform release 不分包（fat apk）
// flutter build apk --flavor platform -t lib/main.dart --dart-define=FLAVOR=platform --release
// google release 分包
// flutter build apk --flavor google -t lib/main.dart --dart-define=FLAVOR=google --release --split-per-abi
// google release 不分包（fat apk）
// flutter build apk --flavor google -t lib/main.dart --dart-define=FLAVOR=google --release




// flutter run --flavor platform --debug
// flutter build apk --flavor platform --release --no-tree-shake-icons --split-per-abi

// flutter run --flavor google --debug
// flutter build apk --flavor google --release --no-tree-shake-icons --split-per-abi




// # Google flavor
// flutter run --flavor google --dart-define=FLAVOR=google --debug

// # Platform flavor
// flutter run --flavor platform --dart-define=FLAVOR=platform --debug

// # web版本打包
// flutter build web --base-href=/qahwa/


// flutter build apk --flavor platform --dart-define=FLAVOR=platform --release --no-tree-shake-icons --split-per-abi

  /// 图片 CDN 地址
  // static const String picRootPath = 'https://image.qahwatv.com/';

  // ==================== 平台标识 ====================
  /// platformId=3;platformAppId=3001  抖音
  /// platformId=2;platformAppId=2001  微信
  /// platformId=2;platformAppId=2002  Android

  /// 越南 Android 平台标识
  static const String androidXClient =
      'platformId=2;platformAppId=2002';

  /// 越南 iOS 平台标识
  static const String iOSXClient =
      'platformId=3;platformAppId=3001';

  /// 当前平台 X-Client（根据运行平台切换）
  /// 【发布前】Android 打包时改为 androidXClient
  /// 【发布前】iOS 打包时改为 iOSXClient
  static String get currentXClient => androidXClient;

  // ==================== 版本号 ====================
  /// Android 版本号
  static const String androidVersion = '1.0.9';

  /// iOS 版本号
  static const String iOSVersion = '1.0.7';

  /// 当前版本号
  static String get appVersion => androidVersion;

  /// Android 资源包版本号（热更新用）
  static const String androidResourceVersion = '1.0.0';

  /// iOS 资源包版本号（热更新用）
  static const String iOSResourceVersion = '1.0.0';

  /// 当前资源包版本号
  static String get resourceVersion => androidResourceVersion;

  // ==================== 支付类型 ====================
  /// Android 支付标识
  static const int payTypeAndroid = 5;
  /// iOS 支付标识
  static const int payTypeiOS = 6;

  // ==================== 当前环境 ====================
  /// 当前平台类型（Android / iOS）
  /// 【发布前】根据打包平台修改此值
  static const String platformType = 'Android';

  // ==================== 客服配置 ====================
  /// 客服 IM ID（与平台标识同步修改）
  static const String imId = '';
}
