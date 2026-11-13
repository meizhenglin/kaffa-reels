import 'package:package_info_plus/package_info_plus.dart';

import 'app_config.dart';
import 'build_flavor.dart';
import 'build_info.dart';

/// 运行时版本号解析。
///
/// 【为什么需要它】
/// 发布包（走 `tool/build.dart`）一定有 `APP_VERSION` / `APP_BUILD_NUMBER`
/// 两个 dart-define，直接取就行。但 **Android Studio 里直接 Run 没有
/// define**，这时只能读原生 `versionName` —— 它同样来自 `pubspec.yaml`，
/// 只是多了渠道后缀（`1.0.6-p` / `1.0.6-g` / `1.0.6-w`）。
///
/// 有了这一层，「改 `pubspec.yaml` 里的版本号」这一件事就够了：
/// 不管是打发布包还是调试运行，请求头里的版本号都对得上。
///
/// 【优先级】
/// 1. dart-define（发布包）
/// 2. 原生 versionName（调试运行）
/// 3. `AppConfig.fallbackVersion`（以上都拿不到）
class AppVersion {
  AppVersion._();

  static ({String base, String full})? _cached;

  /// 请求头 `version=` 的值 —— 不带渠道后缀，例如 `1.0.6`。
  static Future<String> resolveBase() async {
    if (BuildInfo.hasVersion) return BuildInfo.baseVersion;
    return (await _native()).base;
  }

  /// 请求头 `build=` 的值 —— 例如 `1.0.6+15.p`。
  static Future<String> resolveFull() async {
    if (BuildInfo.hasVersion) return BuildInfo.fullVersion;
    return (await _native()).full;
  }

  /// 同步版本，给不需要 await 的地方用（比如日志）。
  ///
  /// 没有 dart-define 时返回的是**兜底常量**，可能比实际版本旧；
  /// 需要准确值请用 [resolveBase] / [resolveFull]。
  static String get syncBase =>
      BuildInfo.hasVersion ? BuildInfo.baseVersion : AppConfig.fallbackVersion;

  static Future<({String base, String full})> _native() async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final info = await PackageInfo.fromPlatform();
      final raw = info.version.trim();

      // 原生 versionName 带渠道后缀：1.0.6-p / 1.0.6-g / 1.0.6-w
      final suffix = '-${BuildFlavor.shortCode}';
      final base = raw.endsWith(suffix)
          ? raw.substring(0, raw.length - suffix.length)
          : raw;

      final buildNumber = info.buildNumber.trim();
      final full = buildNumber.isEmpty
          ? '$base.${BuildFlavor.shortCode}'
          : '$base+$buildNumber.${BuildFlavor.shortCode}';

      return _cached = (
        base: base.isEmpty ? AppConfig.fallbackVersion : base,
        full: full,
      );
    } catch (_) {
      // 读不到原生信息就退回兜底常量，不让请求因为版本号失败。
      return _cached = (
        base: AppConfig.fallbackVersion,
        full: AppConfig.fallbackVersion,
      );
    }
  }
}
