import 'build_flavor.dart';

/// 打包信息：版本号 + 渠道。
///
/// 【唯一真相源】`pubspec.yaml` 里的 `version: 1.0.6+15`。
/// 构建脚本 `tool/build.dart` 会把它拆成两个 dart-define 注入：
///
/// ```
/// --dart-define=APP_VERSION=1.0.6 --dart-define=APP_BUILD_NUMBER=15
/// ```
///
/// 【为什么不用手写常量】之前版本号散落在三处且互不一致：
/// `pubspec.yaml` 是 1.0.6、`AppConfig.androidVersion` 是 1.0.9、
/// iOS 的 `MARKETING_VERSION` 又是另一套。改一处忘另一处必然出事，
/// 而且线上出问题时会分不清装的是哪个包。
///
/// 现在 `AppConfig` 里已经不再有版本号常量了 —— 版本号只有
/// `pubspec.yaml` 一个源头。
///
/// 【拿不到 dart-define 怎么办】在 Android Studio 里直接 Run（没走
/// 构建脚本）时两个 define 都是空串，此时 [hasVersion] 为 false，
/// 界面应当回退到 `package_info_plus` 读原生版本号
/// （Android/iOS 的 versionName 已经带 `-g` / `-p` 后缀）。
class BuildInfo {
  BuildInfo._();

  /// pubspec 的版本号部分（不含 `+buildNumber`）。
  static const String _version = String.fromEnvironment('APP_VERSION');

  /// pubspec 的 build number。
  static const String _buildNumber = String.fromEnvironment('APP_BUILD_NUMBER');

  /// 拿不到版本号时的占位值。
  static const String unknown = '0.0.0';

  /// 构建脚本是否注入了版本号。
  static bool get hasVersion => _version.isNotEmpty;

  /// 纯版本号，例如 `1.0.6`。
  static String get baseVersion => _version.isEmpty ? unknown : _version;

  /// 构建号，例如 `15`。
  static String get buildNumber => _buildNumber.isEmpty ? '0' : _buildNumber;

  /// 当前渠道，取值见 [BuildFlavor]。
  static String get channel => BuildFlavor.current;

  /// 带渠道后缀的版本号，例如 `1.0.6-p` / `1.0.6-g` / `1.0.6-w`。
  ///
  /// 这个字符串就是「这一个包」的完整身份：同一个版本号打三个渠道，
  /// 得到三个互不相同的值，用户在设置页一眼能认出自己装的是哪个。
  static String get displayVersion => '$baseVersion-${BuildFlavor.shortCode}';

  /// 完整标识，包含构建号，例如 `1.0.6+15.p`。
  ///
  /// 用于日志和上报：同一个 version 号的不同构建（改代码重打、
  /// 换配置重打）靠 build number 区分。
  static String get fullVersion =>
      '$baseVersion+$buildNumber.${BuildFlavor.shortCode}';

  /// 供服务端区分渠道与版本的紧凑字段值。
  static String get reportingVersion => '$baseVersion-${BuildFlavor.shortCode}';
}
