import 'package:flutter/foundation.dart';

/// Identifies which product flavor / distribution channel this binary was
/// built for.
///
/// 渠道来源（按优先级）：
/// 1. `FLUTTER_APP_FLAVOR` —— Flutter 在 `flutter build --flavor X` 时
///    **自动注入**的 dart-define（flutter_tools 里 `kAppFlavor`）。
///    所以命令行只要带 `--flavor`，就不需要再手写 `--dart-define=FLAVOR=`。
/// 2. `FLAVOR` —— 手动指定。Web 构建没有 flavor 概念时用它，
///    同时兼容旧命令行。
/// 3. 兜底：Web 构建 → [web]，其余 → [platform]。
class BuildFlavor {
  BuildFlavor._();

  /// Flutter 自动注入的渠道（`flutter build --flavor X` 时存在）。
  static const String _autoFlavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');

  /// 手动指定的渠道（兼容旧命令；Web 构建也走这个）。
  static const String _manualFlavor = String.fromEnvironment('FLAVOR');

  /// Google Play 版本。只有 Google Play 计费，HaiPay 流程关闭。
  static const String google = 'google';

  /// 自建平台版本。HaiPay 与 Google Play 流程都开启。
  static const String platform = 'platform';

  /// Web 版本。Web 没有原生应用商店，版本靠 `web/version.json` + Service Worker。
  static const String web = 'web';

  /// 没有显式指定时的兜底渠道。
  static const String _fallback = kIsWeb ? web : platform;

  /// 当前生效的渠道。
  ///
  /// 这里用 `!= ''` 而不是 `.isNotEmpty`：后者是 getter，不能出现在
  /// const 表达式里。整个判定保持 const，编译器才能把它折叠成常量。
  static const String current = _autoFlavor != ''
      ? _autoFlavor
      : (_manualFlavor != '' ? _manualFlavor : _fallback);

  /// True when this binary is the Google Play build.
  static const bool isGoogle = current == google;

  /// True when this binary is the self-hosted platform build.
  static const bool isPlatform = current == platform;

  /// True when this binary is the Web build.
  static const bool isWeb = current == web;

  /// 版本号里的渠道短码：google → `g`，platform → `p`，web → `w`。
  ///
  /// 与 Android `productFlavors` 里的 `versionNameSuffix` 保持一致，
  /// 这样 Android 原生 versionName（`1.0.6-p`）和 Dart 侧算出来的
  /// `BuildInfo.displayVersion` 永远是同一个字符串。
  static const String shortCode = current == google
      ? 'g'
      : (current == platform ? 'p' : 'w');

  /// Human-readable name (for splash / debug overlays).
  static const String label = current == google
      ? 'Google'
      : (current == platform ? 'Platform' : 'Web');

  /// App display name suffix (debug overlays only — Android uses gradle
  /// productFlavor resValue("string", "app_name", ...) for the launcher).
  static const String appNameSuffix = current == platform ? ' (Platform)' : '';

  /// 品牌名（用户能看到的那个名字）。
  ///
  /// google 渠道是「Qahwa TV」，platform / web 渠道是「Kaffa Reels」。
  /// 与 `tool/build.dart` 的 `_channelAppName` 一一对应 —— 那边决定
  /// 桌面图标名和产物文件名，这边决定界面上的文字和浏览器标签页标题。
  ///
  /// 【为什么需要它】之前品牌名散落在好几个地方，各写各的：
  ///  - `web/index.html` 的 `<title>` → 写死 Kaffa Reels
  ///  - `MaterialApp.title` → 写死 Qahwa TV（来自 AppConstants.appName）
  ///  - 登录页的 `BuildFlavor.isPlatform ? 'Kaffa Reels' : 'Qahwa Tv'`
  ///
  /// 结果是 Web 端加载时标签页标题先显示 Kaffa Reels，Flutter 启动后
  /// 被 `MaterialApp.title` 改成 Qahwa TV，跳一下；而登录页因为
  /// `isPlatform` 对 web 不成立（web 是第三个渠道），直接落到了
  /// Qahwa Tv 那一边。
  ///
  /// 现在只有一个真相源：[brandName]。
  static const String brandName = current == google ? 'Qahwa TV' : 'Kaffa Reels';
}
