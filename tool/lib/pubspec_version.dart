import 'dart:io';

/// `pubspec.yaml` 里的版本号。
///
/// 格式：`主版本.次版本.修订号+构建号`，例如 `1.0.8+16`。
///
/// **构建号可以省略**，但省掉之后 APK 的 `versionCode` 会变成 1 ——
/// Google Play 第一次上传没问题，第二次会因为「version code 1 已被使用」
/// 被拒。所以 [buildNumber] 在省略时返回 `1`，跟 AGP 的默认值保持一致，
/// 保证「请求头里的 build=」和「APK 原生 versionCode」说的是同一件事。
class PubspecVersion {
  const PubspecVersion({
    required this.raw,
    required this.base,
    required this.buildNumber,
    required this.hasBuildNumber,
  });

  /// pubspec.yaml 里 `version:` 后面那串原文，例如 `1.0.8+16`。
  final String raw;

  /// 版本号部分（不含 `+构建号`），例如 `1.0.8`。
  final String base;

  /// 构建号，例如 `16`。
  final String buildNumber;

  /// pubspec.yaml 里有没有写 `+构建号`。
  final bool hasBuildNumber;

  /// 从 `1.0.8+16` 这样的原文解析。
  factory PubspecVersion.parse(String raw) {
    final parts = raw.split('+');
    final hasBuildNumber = parts.length > 1 && parts[1].isNotEmpty;
    return PubspecVersion(
      raw: raw,
      base: parts.first,
      buildNumber: hasBuildNumber ? parts[1] : '1',
      hasBuildNumber: hasBuildNumber,
    );
  }

  /// 从 pubspec.yaml 文件里读版本号。
  ///
  /// 读不到返回 null（调用方负责报错）。
  static PubspecVersion? fromFile(File pubspec) {
    final pattern = RegExp(r'^version:\s*([0-9A-Za-z.\-+]+)\s*$');
    for (final line in pubspec.readAsLinesSync()) {
      final match = pattern.firstMatch(line);
      if (match != null) return PubspecVersion.parse(match.group(1)!);
    }
    return null;
  }
}
