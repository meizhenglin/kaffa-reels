import 'dart:convert';
import 'dart:io';

import 'lib/pubspec_version.dart';

/// 把 app 装到已连接的安卓手机上跑起来（`flutter run`，支持热重载）。
///
/// 版本号和渠道自动从 `pubspec.yaml` 推导，不用手抄 `--dart-define`。
///
/// 用法：
///   dart tool/run.dart                     渠道默认 platform，设备自动挑
///   dart tool/run.dart google              跑谷歌渠道
///   dart tool/run.dart platform 568c2aa4   指定设备
///   dart tool/run.dart google --print      只打印将要执行的命令，不真跑
///   dart tool/run.dart google --release    出 40 MB 的 release 包（无热重载）
///
/// 【为什么用 Dart 写而不是 .bat】
/// cmd 按系统 ANSI 编码解析批处理文件，UTF-8 的中文注释会被解成乱码，
/// 把 `REM` 行截断成要执行的命令，然后疯狂报错。Dart 没有这个坑。
Future<void> main(List<String> args) async {
  var channel = 'platform';
  String? device;
  var printOnly = false;

  // 构建类型。默认 debug（能热重载，但装到手机上约 130 MB）。
  // `--release` 出的是和发布包一样的包（约 40 MB），代价是没有热重载。
  var release = false;

  for (final arg in args) {
    if (arg == '--print') {
      printOnly = true;
    } else if (arg == '--release') {
      release = true;
    } else if (arg.startsWith('--device=')) {
      device = arg.substring('--device='.length);
    } else if (arg == '--help' || arg == '-h') {
      _printUsage();
      return;
    } else if (!arg.startsWith('-')) {
      channel = arg;
    }
  }

  if (channel != 'platform' && channel != 'google') {
    stderr.writeln('✗ 渠道只能是 platform 或 google，收到的是 "$channel"');
    exitCode = 64;
    return;
  }

  // ---------- 版本号 ----------
  final version = PubspecVersion.fromFile(File('pubspec.yaml'));
  if (version == null) {
    stderr.writeln('✗ pubspec.yaml 里读不到 version 字段');
    exitCode = 65;
    return;
  }
  if (!version.hasBuildNumber) {
    stdout.writeln('⚠️ pubspec.yaml 的 version 没写「+构建号」，'
        'APK 的 versionCode 会是 1。');
    stdout.writeln('   第二次上传 Google Play 会因为「version code 1 已被使用」');
    stdout.writeln('   被拒，建议改成 ${version.raw}+2。');
    stdout.writeln('');
  }

  // ---------- 设备 ----------
  final targetDevice = device ?? await _pickAndroidDevice();
  if (targetDevice == null) {
    stderr.writeln('✗ 没找到连着的安卓设备。检查数据线，USB 模式调成「文件传输」，');
    stderr.writeln('   或者在手机的开发者选项里打开「USB 调试」。');
    exitCode = 66;
    return;
  }

  // ---------- 组命令 ----------
  //
  // 【为什么 debug 包这么大】
  //
  // 拆开实际的 debug APK 看过，130+ MB 里绝大部分是这三样：
  //
  // | 内容                                        | 大小    |
  // |---------------------------------------------|---------|
  // | assets/flutter_assets/kernel_blob.bin       | 86.3 MB | ← Dart 调试内核快照
  // | lib/arm64-v8a/libflutter.so                  | 35.8 MB | ← debug 版引擎
  // | lib/arm64-v8a/libVkLayer_khronos_validation.so| 14.5 MB| ← Vulkan 校验层
  //
  // release 包里这三样**都不存在**：没有 kernel_blob（改成 AOT 的
  // libapp.so）、引擎是 release 版、也不带校验层。所以只剩约 40 MB。
  //
  // 【注意】`flutter run` 只打**当前设备那一个 ABI**（flutter_tools 内部
  // 按设备架构决定），所以这里**不需要**、也**不支持** `--target-platform`
  // —— 那是 `flutter build apk` 独有的选项，递给 `flutter run` 会直接报
  //「Could not find an option named "--target-platform"」。
  //
  // 代价：release 没有热重载，改代码要重新构建 + 重装。
  // 只在真机上验证最终效果时才需要。
  final command = <String>[
    'flutter',
    'run',
    '--flavor',
    channel,
    '-d',
    targetDevice,
    if (release) '--release',
    '--dart-define=APP_VERSION=${version.base}',
    '--dart-define=APP_BUILD_NUMBER=${version.buildNumber}',
    '--dart-define=FLAVOR=$channel',
  ];

  stdout.writeln('──────────────────────────────────────────────');
  stdout.writeln('  渠道      $channel');
  stdout.writeln('  设备      $targetDevice');
  stdout.writeln('  构建类型  ${release ? 'release' : 'debug'}');
  stdout.writeln('  版本号    ${version.base}   (构建号 ${version.buildNumber})');
  stdout.writeln('──────────────────────────────────────────────');
  if (!release) {
    stdout.writeln('  提示      debug 包约 130 MB（Dart 调试内核占大头）。');
    stdout.writeln('            想要 40 MB 的小包就加 --release，');
    stdout.writeln('            但那样没有热重载。');
    stdout.writeln('──────────────────────────────────────────────');
  }
  stdout.writeln('');
  stdout.writeln('  ${command.join(' ')}');
  stdout.writeln('');

  if (printOnly) {
    stdout.writeln('  (--print：只打印命令，没有真的跑)');
    return;
  }

  // ---------- 执行 ----------
  //
  // 【必须 inheritStdio，不能只转发 stdout/stderr】
  //
  // flutter run 的热重载靠读终端键盘输入（r=热重载 R=热重启 q=退出）。
  // Process.start 默认不把 stdin 接给子进程 —— 之前只转发输出时，
  // 按键被这个 dart 包装进程吃掉，flutter run 根本收不到，
  // 表现就是「按 r 没反应、不能热重载」。
  // inheritStdio 让 flutter run 直接独占当前终端：
  // 输入、ANSI 颜色、Ctrl+C 行为都和手动跑 flutter run 完全一致。
  final process = await Process.start(
    command.first,
    command.skip(1).toList(),
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
    environment: Platform.environment,
  );

  final code = await process.exitCode;
  exitCode = code;
}

/// 从 `flutter devices --machine` 里挑一台安卓设备。
///
/// 优先真机（`emulator == false`），其次按列表顺序。
Future<String?> _pickAndroidDevice() async {
  final result = await Process.run(
    'flutter',
    ['devices', '--machine'],
    runInShell: true,
  );
  if (result.exitCode != 0) return null;

  List<dynamic> devices;
  try {
    devices = jsonDecode(result.stdout.toString()) as List<dynamic>;
  } catch (_) {
    return null;
  }

  String? fallback;
  for (final entry in devices) {
    if (entry is! Map) continue;
    final platform = '${entry['targetPlatform']}';
    if (!platform.startsWith('android')) continue;
    if (entry['isSupported'] != true) continue;

    final id = '${entry['id']}';
    if (entry['emulator'] == true) {
      fallback ??= id;
      continue;
    }
    return id;
  }
  return fallback;
}

void _printUsage() {
  stdout.writeln('''
用法：
  dart tool/run.dart                     渠道默认 platform，设备自动挑
  dart tool/run.dart google              跑谷歌渠道
  dart tool/run.dart platform 568c2aa4   指定设备
  dart tool/run.dart google --print      只打印将要执行的命令，不真跑
  dart tool/run.dart --device=568c2aa4   用 --device= 传设备也可以

选项：
  --release              出 release 包（约 40 MB），没有热重载。
                         不加就是 debug（约 130 MB），可以热重载。

【debug 包为什么这么大】
  拆开实际的 debug APK 看过，130+ MB 里绝大部分是这三样：

    assets/flutter_assets/kernel_blob.bin         86.3 MB  Dart 调试内核快照
    lib/arm64-v8a/libflutter.so                    35.8 MB  debug 版引擎
    lib/arm64-v8a/libVkLayer_khronos_validation.so 14.5 MB  Vulkan 校验层

  release 包里这三样都不存在（改成 AOT 的 libapp.so、release 版引擎、
  不带校验层），所以只剩约 40 MB。

  只要 40 MB 的包：
    dart tool/run.dart google --release
''');
}
