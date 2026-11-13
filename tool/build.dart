// 统一构建入口。
//
// 一条命令产出 web / google / platform 三个渠道的包，并保证每个包
// 都带上**能区分渠道的版本号**。
//
//   dart tool/build.dart web
//   dart tool/build.dart google --release
//   dart tool/build.dart platform --release --split-per-abi
//
// 【版本号的唯一真相源】pubspec.yaml 的 `version: 1.0.6+15`。
// 脚本把它拆成两个 dart-define 注入：
//
//   --dart-define=APP_VERSION=1.0.6
//   --dart-define=APP_BUILD_NUMBER=15
//
// Dart 侧由 `lib/core/config/build_info.dart` 读取，再拼上渠道短码，
// 得到 `1.0.6-p` / `1.0.6-g` / `1.0.6-w`。Android 的原生 versionName
// 由 Gradle 的 `versionNameSuffix` 产生同样的后缀，两边永远一致。
//
// 【产物文件名也带版本号】构建完成后，脚本会把产物**复制**到
// `build/artifacts/` 并改成带版本号的名字：
//
//   KaffaReels-1.0.6-p-release.apk
//   KaffaReels-1.0.6-p-release-arm64-v8a.apk
//   QahwaTV-1.0.6-g-release.apk
//   KaffaReels-1.0.6-w.zip
//
// 原文件保留在原位（`build/app/outputs/flutter-apk/` 等），不动它们，
// 免得破坏现有的检查脚本。
//
// 【Web 为什么要单独生成 version.json】
// `package_info_plus` 在 Web 上是去站点根目录取 `version.json` 的，
// 而 Flutter 自己不会生成这个文件。缺了它，Web 版设置页的版本号是空的。

import 'dart:convert';
import 'dart:io';

import 'lib/pubspec_version.dart';

import 'package:archive/archive_io.dart';

/// 渠道 → 版本号短码。与 Android `productFlavors` 的 versionNameSuffix 一致。
const Map<String, String> _channelShortCode = <String, String>{
  'google': 'g',
  'platform': 'p',
  'web': 'w',
};

/// 渠道 → 应用名（与 Gradle `resValue("string", "app_name", ...)` 一致）。
const Map<String, String> _channelAppName = <String, String>{
  'google': 'Qahwa TV',
  'platform': 'Kaffa Reels',
  'web': 'Kaffa Reels',
};

/// Flutter 产出的 APK 文件名形如：
/// `app-platform-release.apk` / `app-arm64-v8a-platform-release.apk`。
/// 这里显式列出 ABI，避免把 `armeabi-v7a` 里的连字符切错。
const List<String> _knownAbis = <String>[
  'armeabi-v7a',
  'arm64-v8a',
  'x86_64',
  'x86',
];

/// 产物统一放这里。
const String _artifactDir = 'build/artifacts';

/// 记录各渠道用过的 versionCode，用来检查有没有倒退。
const String _versionCodeStateFile = 'build/.version-code.json';

Future<void> main(List<String> args) async {
  final _Options options;
  try {
    options = _Options.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('✗ ${e.message}');
    exitCode = 64;
    return;
  }

  if (options.help) {
    _printUsage();
    return;
  }

  final target = options.target;
  if (target == null || !_channelShortCode.containsKey(target)) {
    stderr.writeln('✗ 目标必须是 web / google / platform 之一');
    _printUsage();
    exitCode = 64;
    return;
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('✗ 找不到 pubspec.yaml，请在项目根目录运行');
    exitCode = 66;
    return;
  }

  final version = PubspecVersion.fromFile(pubspec);
  if (version == null) {
    stderr.writeln('✗ pubspec.yaml 里读不到 version 字段');
    exitCode = 65;
    return;
  }

  // pubspec 没写 `+构建号` 时，AGP 会用默认的 versionCode = 1。
  // 这里跟着用 1，保证「请求头里的 build=」和「APK 原生 versionCode」
  // 说的是同一件事。
  final baseVersion = version.base;
  final hasBuildNumber = version.hasBuildNumber;
  // `--version-code=N` 可以覆盖构建号 —— 它同时决定 APK 的 versionCode
  // 和请求头里的 build=，两者必须一致。
  final buildNumber = options.versionCode != null
      ? options.versionCode.toString()
      : version.buildNumber;
  final shortCode = _channelShortCode[target]!;
  final displayVersion = '$baseVersion-$shortCode';
  final fullVersion = '$baseVersion+$buildNumber.$shortCode';
  final appName = options.appName ?? _channelAppName[target]!;

  stdout.writeln('──────────────────────────────────────────────');
  stdout.writeln('  渠道      $target');
  stdout.writeln('  应用名    $appName');
  stdout.writeln('  版本号    $displayVersion   (完整标识 $fullVersion)');
  stdout.writeln('  构建类型  ${options.release ? 'release' : 'debug'}');
  stdout.writeln('──────────────────────────────────────────────');

  if (options.versionCode != null) {
    stdout.writeln('  versionCode  ${options.versionCode}  (由 --version-code 指定)');
    stdout.writeln('');
  }

  if (!hasBuildNumber) {
    stdout.writeln('');
    stdout.writeln('  ⚠️ pubspec.yaml 的 version 后面没写「+构建号」：');
    stdout.writeln('     当前是 ${version.raw}，APK 的 versionCode 会是 1。');
    stdout.writeln('     第一次上传 Google Play 没问题，但第二次上传会因为');
    stdout.writeln('     「versionCode 1 已被使用」被拒。');
    stdout.writeln('     建议改成  ${version.raw}+2  （构建号必须每次递增）。');
    stdout.writeln('');
  }

  // versionCode 倒退检查放在这里 —— dry-run 也要能看到。
  if (target != 'web' && target != 'ios') {
    _checkVersionCodeNotGoingBackwards(target, buildNumber);
  }

  if (target == 'web') {
    _writeWebVersionFile(
      version: displayVersion,
      buildNumber: buildNumber,
      appName: appName,
    );
  }

  if (options.artifactsOnly) {
    // 跳过构建，只对已有的产物做重命名。
    // 用于「已经用 flutter build 手动打过包」的场景 —— Flutter 把
    // app-<abi>-<flavor>-<mode>.apk 这个文件名写死在 FlutterPlugin.kt 里，
    // Gradle 侧改不了最终落到 flutter-apk 的名字，只能事后重命名。
    stdout.writeln('· --artifacts-only：不执行构建，只处理已有产物');
    stdout.writeln('');
    final produced = await _collectArtifacts(
      target: target,
      appName: appName,
      baseVersion: baseVersion,
      displayVersion: displayVersion,
      buildType: _inferBuildType(target),
    );
    _printArtifacts(produced);
    return;
  }

  final flutterArgs = <String>[
    'build',
    if (target == 'web') 'web' else if (target == 'ios') 'ipa' else if (options.appBundle) 'appbundle' else 'apk',
    if (target == 'google' || target == 'platform') ...['--flavor', target],
    if (options.release) '--release' else '--debug',
    // AAB 由 Google Play 自己按 ABI 拆分，不能再加 --split-per-abi。
    if (options.splitPerAbi && !options.appBundle) ...['--split-per-abi'],
    // --target-platform 是给 APK 用的；AAB 里会带上所有 ABI。
    if (target != 'web' && target != 'ios' && !options.appBundle)
      ...[
        '--target-platform',
        options.targetPlatform ?? _defaultTargetPlatform(options.release),
      ],
    if (target == 'web' && options.baseHref != null)
      '--base-href=${options.baseHref}',
    if (target != 'web' && options.versionCode != null)
      '--build-number=${options.versionCode}',
    '--dart-define=APP_VERSION=$baseVersion',
    '--dart-define=APP_BUILD_NUMBER=$buildNumber',
    // Flutter 在 `--flavor` 时会自动注入 FLUTTER_APP_FLAVOR；
    // 这里再显式给一份 FLAVOR，Web 构建（没有 flavor 概念）靠它，
    // 其余情况作为兜底。两份值一致，不会冲突。
    '--dart-define=FLAVOR=$target',
  ];

  stdout.writeln('> flutter ${flutterArgs.join(' ')}');
  stdout.writeln('');

  if (options.dryRun) {
    stdout.writeln('✓ --dry-run：只打印命令，未执行构建');
    return;
  }

  // 清理放在 dry-run 判断之后 —— --dry-run 不该动任何文件。
  if (target != 'web' && target != 'ios') {
    final platforms =
        options.targetPlatform ?? _defaultTargetPlatform(options.release);
    _prepareAndroidBuild(platforms.split(','));
    if (options.appBundle) _clearBundleOutput();
  }

  final flutterBin = Platform.environment['FLUTTER_BIN'] ?? 'flutter';
  final process = await Process.start(
    flutterBin,
    flutterArgs,
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    stderr.writeln('✗ 构建失败，退出码 $code');
    exitCode = code;
    return;
  }

  stdout.writeln('');
  stdout.writeln('✓ 构建完成：$target  $fullVersion');

  // 记下这个渠道用过的 versionCode，下次构建时用来检查有没有倒退。
  if (target != 'web' && target != 'ios') {
    _recordVersionCode(target, buildNumber);
  }

  if (options.noArtifacts) {
    stdout.writeln('· --no-artifacts：跳过产物重命名');
    return;
  }

  final produced = await _collectArtifacts(
    target: target,
    appName: appName,
    baseVersion: baseVersion,
    displayVersion: displayVersion,
    buildType: options.release ? 'release' : 'debug',
  );

  _printArtifacts(produced);
}

/// 记录「这个渠道用过的 versionCode」。
///
/// Google Play 要求每次上传的 versionCode 都大于之前所有上传过的。
/// 这里把上一次用过的值记下来，下次构建时据此提醒 —— 防止「改了
/// 版本号但忘了递增构建号」，那种包传上去会被 Play 直接拒掉。
///
/// 记录文件放在 `build/` 里（不进版本库），`flutter clean` 之后会丢，
/// 丢了只是不再提醒，不影响正确性。
void _recordVersionCode(String target, String buildNumber) {
  final file = File(_versionCodeStateFile);
  Map<String, dynamic> state = {};
  if (file.existsSync()) {
    try {
      state = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      state = {};
    }
  }
  state[target] = buildNumber;
  try {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(state));
  } on FileSystemException catch (e) {
    stdout.writeln('· 未能记录 versionCode：${e.message}');
  }
}

/// 检查 versionCode 没有比上一次用过的更小。
void _checkVersionCodeNotGoingBackwards(String target, String buildNumber) {
  final file = File(_versionCodeStateFile);
  if (!file.existsSync()) return;

  Map<String, dynamic> state;
  try {
    state = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  final previous = state[target];
  if (previous is! String) return;

  final previousCode = int.tryParse(previous);
  final currentCode = int.tryParse(buildNumber);
  if (previousCode == null || currentCode == null) return;
  if (currentCode > previousCode) return;

  stdout.writeln('');
  stdout.writeln('  ⚠️ versionCode 没有递增：');
  stdout.writeln('     上一次 $target 用的是 $previousCode，这次是 $currentCode。');
  stdout.writeln('     Google Play 要求每次上传的 versionCode 更大，');
  stdout.writeln('     传上去会被直接拒掉。');
  stdout.writeln('     把 pubspec.yaml 的 version 改成 ${previousCode + 1} 以上，');
  stdout.writeln('     或者用 --version-code=${previousCode + 1} 覆盖。');
  stdout.writeln('');
}

/// 打印产物清单。
void _printArtifacts(List<File> produced) {
  if (produced.isEmpty) {
    stdout.writeln('· 没有找到可重命名的产物');
    return;
  }
  stdout.writeln('');
  stdout.writeln('✓ 产物（$_artifactDir）：');
  for (final file in produced) {
    final size = (file.lengthSync() / 1024 / 1024).toStringAsFixed(1);
    stdout.writeln('  ${file.path}  ($size MB)');
  }
}

/// 推断已有产物是哪种构建类型（release / debug）。
///
/// `--artifacts-only` 场景下用户是自己敲 `flutter build` 的，脚本不知道
/// 他们用了什么参数。取「该渠道下最新产出的 APK」所属的构建类型。
String _inferBuildType(String target) {
  if (target == 'web') return 'release';
  final apkDir = Directory('build/app/outputs/flutter-apk');
  if (!apkDir.existsSync()) return 'release';

  File? newest;
  for (final entity in apkDir.listSync()) {
    if (entity is! File || !entity.path.toLowerCase().endsWith('.apk')) {
      continue;
    }
    if (_parseFlutterApkName(_baseName(entity)).flavor != target) {
      continue;
    }
    if (newest == null ||
        entity.lastModifiedSync().isAfter(newest.lastModifiedSync())) {
      newest = entity;
    }
  }
  if (newest == null) return 'release';
  return _parseFlutterApkName(_baseName(newest)).buildType;
}

/// 读取 pubspec.yaml 顶层的 `version: 1.0.6+15`。
/// 生成 `web/version.json`。
///
/// `package_info_plus` 在 Web 上就是读这个文件；没有它，Web 版设置页
/// 显示的版本号是空的。同时把 `web/manifest.json` 里的应用名对齐，
/// 否则 PWA 安装后的名字还是工程名。
void _writeWebVersionFile({
  required String version,
  required String buildNumber,
  required String appName,
}) {
  final versionFile = File('web/version.json');
  versionFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(<String, String>{
      'app_name': appName,
      'version': version,
      'build_number': buildNumber,
      'package_name': 'com.video.storydrama',
    }),
  );
  stdout.writeln('✓ 已生成 web/version.json');

  final manifestFile = File('web/manifest.json');
  if (!manifestFile.existsSync()) return;
  final decoded = jsonDecode(manifestFile.readAsStringSync());
  if (decoded is! Map<String, dynamic>) return;
  decoded['name'] = appName;
  decoded['short_name'] = appName;
  manifestFile.writeAsStringSync(
    const JsonEncoder.withIndent('    ').convert(decoded),
  );
  stdout.writeln('✓ 已更新 web/manifest.json 的应用名');
}

/// 收集构建产物并复制成带版本号文件名的副本。
///
/// **只复制不移动**：现有的 `check_apk.ps1` 等脚本按固定路径找原始 APK，
/// 移走会让它们失效。
///
/// 【必须按渠道 + 构建类型筛选】`build/app/outputs/flutter-apk/` 是**累积**的
/// 目录，历次构建的 APK 都躺在里面（实测同时存在 google 渠道的 debug 包和
/// platform 渠道的 release 包）。不筛选的话会把别的渠道的包也复制进来，
/// 而且都叫同一个名字互相覆盖。
Future<List<File>> _collectArtifacts({
  required String target,
  required String appName,
  required String baseVersion,
  required String displayVersion,
  required String buildType,
}) async {
  final outDir = Directory(_artifactDir);
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  final prefix = '${_sanitizeFileName(appName)}-$displayVersion';
  final produced = <File>[];

  // 先把「同渠道、同构建类型、但版本号更旧」的产物清掉，
  // 免得目录里同时躺着 1.0.6 和 1.0.7，上传时挑错。
  final removed = _removeStaleArtifacts(
    appName: appName,
    shortCode: _channelShortCode[target]!,
    buildType: target == 'web' ? '' : buildType,
    currentVersion: baseVersion,
  );
  for (final name in removed) {
    stdout.writeln('· 清理旧产物：$name');
  }

  if (target == 'web') {
    final webDir = Directory('build/web');
    if (!webDir.existsSync()) return produced;
    final zipFile = await _zipDirectory(webDir, '$_artifactDir/$prefix.zip');
    produced.add(zipFile);
    return produced;
  }

  // Android：build/app/outputs/flutter-apk/*.apk
  final apkDir = Directory('build/app/outputs/flutter-apk');
  if (apkDir.existsSync()) {
    final candidates = <File, _ApkName>{};
    for (final entity in apkDir.listSync()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.apk')) {
        continue;
      }
      final parsed = _parseFlutterApkName(_baseName(entity));
      // 渠道必须一致，否则会把 google 的包当成 platform 的产物。
      if (parsed.flavor != target) continue;
      // 构建类型必须一致，否则 release 构建会捎带上旧的 debug 包。
      if (parsed.buildType != buildType) continue;
      candidates[entity] = parsed;
    }

    // 构建前已经清空过 flutter-apk 目录（见 _clearFlutterApkOutput），
    // 里面的 APK 必然都是本次构建的，所以这里只按渠道 + 构建类型
    // 过滤就足够了。
    //
    // 【为什么不用时间窗口过滤】之前用「与最新文件相差 60 秒内」来判断
    // 是否同一批产物，但慢速构建（超过 60 秒）会误删先产出的那个 APK。
    // 清空目录的方案既准确又没有这个副作用。

    for (final entry in candidates.entries) {
      final parsed = entry.value;
      final suffix = parsed.abi == null
          ? parsed.buildType
          : '${parsed.buildType}-${parsed.abi}';
      final copy = File('$_artifactDir/$prefix-$suffix.apk');
      entry.key.copySync(copy.path);
      produced.add(copy);
    }
  }

  // Android AAB：build/app/outputs/bundle/<变体>/<构建类型>/*.aab
  final bundleDir = Directory('build/app/outputs/bundle');
  if (bundleDir.existsSync()) {
    for (final variantDir in bundleDir.listSync()) {
      if (variantDir is! Directory) continue;
      for (final entity in variantDir.listSync()) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.aab')) continue;
        // 渠道必须一致：google 的 aab 不能当成 platform 的产物。
        if (!_baseName(entity).contains(target)) continue;
        // 命名跟 APK 保持一致：<应用名>-<版本>-<渠道>-<构建类型>.aab
        final copy = File('$_artifactDir/$prefix-$buildType.aab');
        entity.copySync(copy.path);
        produced.add(copy);
      }
    }
  }

  // iOS：build/ios/ipa/*.ipa
  final ipaDir = Directory('build/ios/ipa');
  if (ipaDir.existsSync()) {
    for (final entity in ipaDir.listSync()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.ipa')) {
        continue;
      }
      final copy = File('$_artifactDir/$prefix.ipa');
      entity.copySync(copy.path);
      produced.add(copy);
    }
  }

  return produced;
}

/// 把目录打成 zip。
///
/// 【为什么要重试】Windows 上刚创建的文件常被杀毒软件抢先去扫描，
/// 我们的写操作会收到 `errno=5 拒绝访问`。先写临时文件再改名，
/// 并做有限次重试即可绕开这个竞态。
///
/// 【includeDirName 必须为 false】`ZipFileEncoder.addDirectory` 默认会把
/// 目录名当一层前缀（`web/index.html`），部署时要的是 `index.html`
/// 直接在压缩包根目录。
Future<File> _zipDirectory(Directory dir, String destPath) async {
  Object? lastError;
  for (var attempt = 1; attempt <= 3; attempt++) {
    final tmpPath = '$destPath.tmp';
    try {
      final tmpFile = File(tmpPath);
      if (tmpFile.existsSync()) tmpFile.deleteSync();

      final encoder = ZipFileEncoder();
      encoder.create(tmpPath);
      await encoder.addDirectory(dir, includeDirName: false);
      await encoder.close();

      final dest = File(destPath);
      if (dest.existsSync()) dest.deleteSync();
      tmpFile.renameSync(destPath);
      return dest;
    } catch (e) {
      lastError = e;
      stdout.writeln('· 打包 Web 产物失败，重试 $attempt/3：$e');
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }
  throw StateError('打包 Web 产物失败：$lastError');
}

/// 清理同渠道、同构建类型、但版本号更旧的产物文件。
///
/// 产物文件名形如：
///   `KaffaReels-1.0.6-p-release.apk`
///   `KaffaReels-1.0.6-p-release-arm64-v8a.apk`
///   `KaffaReels-1.0.6-w.zip`
///
/// 只删**同渠道**的旧版本 —— google 和 platform 的产物可以并存。
/// 不同构建类型也保留（debug 和 release 互不干扰）。
///
/// [buildType] 传空字符串表示不限构建类型（Web 只有一个 zip）。
List<String> _removeStaleArtifacts({
  required String appName,
  required String shortCode,
  required String buildType,
  required String currentVersion,
}) {
  final dir = Directory(_artifactDir);
  if (!dir.existsSync()) return const [];

  final escaped = RegExp.escape(_sanitizeFileName(appName));
  // 文件名结构：<应用名>-<版本>-<渠道>[-<构建类型>[-<abi>]].<ext>
  // 注意 ABI 里带连字符（arm64-v8a / armeabi-v7a），所以 ABI 段要允许 '-'。
  // 版本号用非贪婪匹配，避免把后面的渠道短码吞进版本里。
  final pattern = buildType.isEmpty
      ? RegExp('^$escaped-(.+?)-$shortCode\\.(apk|ipa|zip)\$')
      : RegExp(
          '^$escaped-(.+?)-$shortCode-$buildType'
          '(-[a-zA-Z0-9_-]+)?\\.(apk|ipa|zip)\$',
        );

  final removed = <String>[];
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final name = _baseName(entity);
    final match = pattern.firstMatch(name);
    if (match == null) continue;
    final version = match.group(1)!;
    if (version == currentVersion) continue;
    entity.deleteSync();
    removed.add(name);
  }
  return removed;
}

/// 解析 Flutter 生成的 APK 文件名。
///
/// `app-platform-release.apk` → flavor=platform, buildType=release, abi=null
/// `app-arm64-v8a-platform-release.apk` → abi=arm64-v8a
class _ApkName {
  const _ApkName(this.flavor, this.buildType, this.abi);

  final String flavor;
  final String buildType;
  final String? abi;
}

_ApkName _parseFlutterApkName(String fileName) {
  final abiPattern = _knownAbis.join('|');
  final pattern = RegExp(
    '^app-(?:($abiPattern)-)?(google|platform)-(debug|release|profile)\\.apk\$',
  );
  final match = pattern.firstMatch(fileName);
  if (match == null) {
    // 认不出来就退回「去掉 app- 前缀」，至少不会把版本号丢掉。
    final base = fileName.replaceFirst(
      RegExp(r'\.apk\$', caseSensitive: false),
      '',
    );
    return _ApkName('unknown', base.replaceFirst('app-', ''), null);
  }
  return _ApkName(match.group(2)!, match.group(3)!, match.group(1));
}

/// 取文件/目录的 basename。
///
/// **不能用 `entity.uri.pathSegments.last`**：`Directory.uri` 会自动补一个
/// 结尾斜杠，`pathSegments.last` 于是变成空字符串，目录名一个都匹配不上。
/// `File.uri` 没这个问题，但为了统一，两边都用路径切分。
String _baseName(FileSystemEntity entity) {
  final parts = entity.path.split(RegExp(r'[/\\]'));
  for (var i = parts.length - 1; i >= 0; i--) {
    if (parts[i].isNotEmpty) return parts[i];
  }
  return '';
}

/// `--target-platform` 的值 → APK 里的 ABI 目录名。
const Map<String, String> _targetPlatformToAbiDir = <String, String>{
  'android-arm': 'armeabi-v7a',
  'android-arm64': 'arm64-v8a',
  'android-x64': 'x86_64',
};

/// 构建 Android 前清理中间产物。
///
/// **两个坑，都要处理**：
///
/// ① **x86_64 残留**。`flutter build apk` 默认会带上 `android-x64`，
/// 于是 libflutter.so + libapp.so 各多一份 x86_64 副本，整包多占约
/// 21 MB。Google Play 只要求 arm64-v8a / armeabi-v7a，x86_64 只有
/// 模拟器用得上。而 Flutter 的 Gradle 任务只为目标 ABI 建目录，
/// **不会删旧 ABI 的目录**，所以要主动清理。
///
/// ② **AGP 的 merge 任务不会重新合并**（这个更隐蔽、更要命）。
/// Flutter 重新编译 Dart 代码后，`flutter/<变体>/jniLibs/<abi>/libapp.so`
/// 确实更新了，但 AGP 的 `mergePlatformReleaseJniLibFolders` 任务仍被判定
/// 为 **UP-TO-DATE** —— 它没有跟踪 Flutter 的 jniLibs 输入。连带
/// `mergePlatformReleaseNativeLibs`、`stripPlatformReleaseDebugSymbols`
/// 也全部跳过，最终打出来的 APK 里烧的是**上一次的 Dart 代码**。
///
/// 实测：连续两次构建只改 `--dart-define=APP_VERSION`，第二次的 APK 里
/// 仍然是第一次的版本号（`5.5.5` 而不是 `6.6.6`）。改 pubspec 版本号
/// 再打包，同样会出现「装上去还是旧版本」。
///
/// 解法是把 AGP 的合并/剥离产物整个删掉，逼它们重算。这几个目录是纯
/// 中间产物，重算一次几秒钟。
void _prepareAndroidBuild(List<String> targetPlatforms) {
  _cleanStaleAbiDirs(targetPlatforms);
  _invalidateNativeLibCache();
  _clearFlutterApkOutput();
}

/// 构建前清空 `build/app/outputs/flutter-apk/`。
///
/// 这个目录是 Flutter 把 APK 从 AGP 的输出目录**复制**出来的地方，
/// 是**累积**的：历次构建的包都躺在里面，而且**不带任何版本信息**，
/// 只有 `app-<abi>-<渠道>-<构建类型>.apk` 这种名字。
///
/// 后果是收集产物时可能捡到上一轮的旧包。比如先打整包、再打
/// `--split-per-abi`，目录里会同时有旧的整包和新的拆分包；
/// 旧包会被当成当前产物复制到 `build/artifacts/`，还会被冠上当前的
/// 版本号 —— 名字写着 1.0.6，里面烧的却是 1.0.7 的代码。
///
/// 构建前整个删掉，目录里就只可能有本次构建的产物。Flutter 每次构建
/// 都会重新复制，不受影响。
void _clearFlutterApkOutput() {
  final dir = Directory('build/app/outputs/flutter-apk');
  if (!dir.existsSync()) return;
  try {
    dir.deleteSync(recursive: true);
    stdout.writeln('· 清空上次构建的 APK 输出目录');
  } on FileSystemException catch (e) {
    stdout.writeln('· 未能清空 $dir：${e.message}');
  }
}

/// 清空 `build/app/outputs/bundle/`（AAB 的输出目录）。
///
/// 和 `flutter-apk` 一样是累积的：不清理的话，上一轮的 `.aab` 会留在
/// 那里，被当成本次产物复制到 `build/artifacts/`。
void _clearBundleOutput() {
  final dir = Directory('build/app/outputs/bundle');
  if (!dir.existsSync()) return;
  try {
    dir.deleteSync(recursive: true);
    stdout.writeln('· 清空上次构建的 AAB 输出目录');
  } on FileSystemException catch (e) {
    stdout.writeln('· 未能清空 $dir：${e.message}');
  }
}

/// 清理 Flutter 目录下上次残留的 ABI 目录。
///
/// 只动 `intermediates/flutter/` —— 这是 Flutter 自己的任务输出，
/// 删了下次会重新生成，也不会破坏 Gradle 的任务状态。
void _cleanStaleAbiDirs(List<String> targetPlatforms) {
  final flutterIntermediates = Directory('build/app/intermediates/flutter');
  if (!flutterIntermediates.existsSync()) return;

  final wanted = <String>{
    for (final platform in targetPlatforms)
      if (_targetPlatformToAbiDir[platform] != null)
        _targetPlatformToAbiDir[platform]!,
  };
  if (wanted.isEmpty) return;

  final unwanted = _knownAbis.where((abi) => !wanted.contains(abi)).toSet();
  if (unwanted.isEmpty) return;

  for (final variantDir in flutterIntermediates.listSync()) {
    if (variantDir is! Directory) continue;
    for (final entry in variantDir.listSync()) {
      if (entry is! Directory) continue;
      final name = _baseName(entry);
      if (!unwanted.contains(name)) continue;
      entry.deleteSync(recursive: true);
      stdout.writeln('· 清理残留 ABI 目录：${entry.path}');
    }
  }
}

/// 让 AGP 的原生库合并/剥离任务重新执行。
///
/// 这三个目录是「上一次构建的原生库合并结果」。只要它们还在，
/// Gradle 就会判定 merge / strip 任务是 UP-TO-DATE，于是新编译出来的
/// Dart 代码进不了 APK —— 装到手机上跑的还是旧版本。
///
/// 删除后，Gradle 发现输出缺失，会重新执行：
///   mergePlatformReleaseJniLibFolders
///   → mergePlatformReleaseNativeLibs
///   → stripPlatformReleaseDebugSymbols
///   → packagePlatformRelease
void _invalidateNativeLibCache() {
  const stale = <String>[
    'build/app/intermediates/merged_jni_libs',
    'build/app/intermediates/merged_native_libs',
    'build/app/intermediates/stripped_native_libs',
  ];
  for (final path in stale) {
    final dir = Directory(path);
    if (!dir.existsSync()) continue;
    try {
      dir.deleteSync(recursive: true);
      stdout.writeln('· 失效原生库合并缓存：$path');
    } on FileSystemException catch (e) {
      // 删不掉（比如文件被占用）不算致命，后面还有校验兜底。
      stdout.writeln('· 未能清理 $path：${e.message}');
    }
  }
}

/// 默认的 `--target-platform`。
///
/// **为什么 release 要去掉 x86_64**：`flutter build apk` 默认会带上
/// `android-x64`，于是 libflutter.so + libapp.so 各多一份 x86_64 副本，
/// 整包多占约 21 MB。Google Play 只要求 arm64-v8a / armeabi-v7a，
/// x86_64 只有模拟器用得上。
///
/// debug 保留 x86_64，因为要在 x86 模拟器上跑。
String _defaultTargetPlatform(bool release) => release
    ? 'android-arm,android-arm64'
    : 'android-arm,android-arm64,android-x64';

/// 文件名里不能有空格，用短横线或直接去掉。
String _sanitizeFileName(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), '');

void _printUsage() {
  stdout.writeln('''
用法：
  dart tool/build.dart <web|google|platform> [选项]

选项：
  --release            release 构建（默认）
  --debug              debug 构建
  --split-per-abi      Android 按 ABI 拆分（默认整包）
  --appbundle          打 Android App Bundle（.aab），上传 Google Play 用。
                      和 --split-per-abi 互斥：AAB 里包含所有 ABI，
                      由 Play 自己按设备分发，versionCode 不用分着递增。
  --app-name=<name>    覆盖应用名（默认按渠道取）
  --target-platform=<list>
                      Android 的 ABI 列表，逗号分隔。可选值：
                      android-arm / android-arm64 / android-x64。
                      默认 release 只打 arm + arm64（去掉 x86_64，
                      省约 21 MB）；debug 三个都打，方便跑 x86 模拟器。
  --no-artifacts        构建后不做产物重命名
  --artifacts-only      不执行构建，只对已有产物重命名
  --version-code=N      覆盖 versionCode（= 构建号），同时写进
                        请求头的 build=。从「拆分 APK」切到 AAB 时
                        versionCode 会变小（拆分 APK 的 arm64 是
                        构建号+2000，AAB 就是构建号），而 Google Play
                        要求每次上传的 versionCode 更大 —— 用这个
                        开关直接指定一个够大的值。
  --dry-run            只打印将要执行的命令，不真的构建
  --base-href=<path>   Web 的 base href，例如 /app/
  -h, --help           显示本帮助

产物（构建后生成在 $_artifactDir）：
  <应用名>-<版本>-<渠道>[-<abi>]-<构建类型>.apk
  <应用名>-<版本>-<渠道>-<构建类型>.aab   （--appbundle）
  <应用名>-<版本>-<渠道>.zip      （Web）

【已经用 flutter build 手动打过包？】
Flutter 把 `app-<abi>-<渠道>-<构建类型>.apk` 这个文件名写死在
flutter_tools 的 FlutterPlugin.kt 里，Gradle 侧改不了最终落到
flutter-apk 的名字，只能事后重命名：

  flutter build apk --flavor platform --release --split-per-abi
  dart tool/build.dart platform --artifacts-only
''');
}

class _Options {
  _Options({
    required this.target,
    required this.release,
    required this.splitPerAbi,
    required this.baseHref,
    required this.appName,
    required this.help,
    required this.dryRun,
    required this.noArtifacts,
    required this.artifactsOnly,
    required this.targetPlatform,
    required this.appBundle,
    required this.versionCode,
  });

  final String? target;
  final bool release;
  final bool splitPerAbi;
  final String? baseHref;
  final String? appName;
  final bool help;
  final bool dryRun;
  final bool noArtifacts;
  final bool artifactsOnly;
  final String? targetPlatform;

  /// 打 Android App Bundle（`.aab`）而不是 APK。
  ///
  /// 上传 Google Play 用这个：一个 AAB 里包含所有 ABI，Play 自己按设备
  /// 分发，**不会出现「多个 ABI 的 APK 各自要递增 versionCode」的问题**。
  final bool appBundle;

  /// 覆盖 versionCode（= 构建号）。
  ///
  /// 场景：从「拆分 APK」切到「AAB」时，versionCode 会变小
  /// （拆分 APK 的 arm64 是 构建号+2000，AAB 就是 构建号），
  /// 而 Google Play 要求每次上传的 versionCode 更大。用这个开关
  /// 可以直接指定一个够大的值，不用去改 pubspec.yaml 里的构建号。
  final int? versionCode;

  factory _Options.parse(List<String> args) {
    String? target;
    var release = true;
    var splitPerAbi = false;
    String? baseHref;
    String? appName;
    var help = false;
    var dryRun = false;
    var noArtifacts = false;
    var artifactsOnly = false;
    String? targetPlatform;
    var appBundle = false;
    int? versionCode;

    for (final arg in args) {
      if (arg.startsWith('--base-href=')) {
        baseHref = arg.substring('--base-href='.length);
      } else if (arg.startsWith('--app-name=')) {
        appName = arg.substring('--app-name='.length);
      } else if (arg.startsWith('--target-platform=')) {
        targetPlatform = arg.substring('--target-platform='.length);
      } else if (arg == '--release') {
        release = true;
      } else if (arg == '--debug') {
        release = false;
      } else if (arg == '--split-per-abi') {
        splitPerAbi = true;
      } else if (arg == '--dry-run') {
        dryRun = true;
      } else if (arg == '--no-artifacts') {
        noArtifacts = true;
      } else if (arg == '--artifacts-only') {
        artifactsOnly = true;
      } else if (arg.startsWith('--version-code=')) {
        final raw = arg.substring('--version-code='.length);
        final parsed = int.tryParse(raw);
        if (parsed == null || parsed <= 0) {
          throw FormatException(
            '--version-code 需要一个正整数，收到的是 "$raw"',
          );
        }
        versionCode = parsed;
      } else if (arg == '--appbundle' || arg == '--aab') {
        appBundle = true;
      } else if (arg == '-h' || arg == '--help') {
        help = true;
      } else if (!arg.startsWith('-')) {
        target = arg;
      }
    }

    return _Options(
      target: target,
      release: release,
      splitPerAbi: splitPerAbi,
      baseHref: baseHref,
      appName: appName,
      help: help,
      dryRun: dryRun,
      noArtifacts: noArtifacts,
      artifactsOnly: artifactsOnly,
      targetPlatform: targetPlatform,
      appBundle: appBundle,
      versionCode: versionCode,
    );
  }
}
