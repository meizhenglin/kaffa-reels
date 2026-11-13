// 一次性诊断脚本：在真机上运行的 App 里执行 Dart 表达式，
// 用来查看 App 实际拿到的后端数据（商品列表 / 支付配置）。
//
// 用法：
//   dart tool\vm_eval.dart "<dart表达式>"
//   dart tool\vm_eval.dart --lib=core/network/api_service.dart "<表达式>"
//   dart tool\vm_eval.dart --file=build/expr.dart
//
// `--lib=` 指定在哪个库的作用域里求值（默认 main.dart）。
// 表达式里的引号在 PowerShell 里容易被吃掉，放文件里更保险。
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  // 可选：--lib=<uri 子串> 指定在哪个库的作用域里求值。
  // 默认在 main.dart 里求值；要调用某个库里的类，就指定那个库。
  // 可选：--file=<路径> 从文件读表达式（避开 shell 的引号转义问题）。
  String? libHint;
  String? exprFile;
  String? vmUrl;
  final exprArgs = <String>[];
  for (final a in args) {
    if (a.startsWith('--lib=')) {
      libHint = a.substring('--lib='.length);
    } else if (a.startsWith('--file=')) {
      exprFile = a.substring('--file='.length);
    } else if (a.startsWith('--url=')) {
      vmUrl = a.substring('--url='.length);
    } else {
      exprArgs.add(a);
    }
  }
  if (exprArgs.isEmpty && exprFile == null) {
    stderr.writeln('用法: dart tool\\vm_eval.dart <dart表达式>');
    exit(2);
  }
  final expression = exprFile != null
      ? File(exprFile).readAsStringSync()
      : exprArgs.join(' ');

  final adb = _adbPath();
  if (adb == null) {
    stderr.writeln('找不到 adb');
    exit(1);
  }

  final candidates = vmUrl != null
      ? [_wsFromHttp(Uri.parse(vmUrl))]
      : await _vmServiceCandidates(adb);
  if (candidates.isEmpty) {
    stderr.writeln('找不到 VM service，先用 dart tool\\run.dart 起一个 debug 包');
    exit(1);
  }

  VmService? service;
  String? isolateId;
  IsolateRef? isolate;
  // logcat 里会堆着历次运行的地址，从最新往回试，直到连上。
  for (final uri in candidates) {
    try {
      final s = await vmServiceConnectUri(uri.toString());
      final vm = await s.getVM();
      final iso = vm.isolates!.firstWhere((i) => i.name == 'main');
      service = s;
      isolateId = iso.id!;
      isolate = iso;
      break;
    } catch (_) {
      // 试下一个。
    }
  }
  if (service == null || isolateId == null || isolate == null) {
    stderr.writeln('连不上 VM service，试了 ${candidates.length} 个地址');
    exit(1);
  }

  // targetId 用 isolate 的 rootLib —— 表达式就在该库的作用域里求值。
  final isolateInfo = await service.getIsolate(isolateId);
  var targetLibId = isolateInfo.rootLib!.id!;
  if (libHint != null) {
    final hint = libHint;
    final lib = isolateInfo.libraries!.firstWhere(
      (l) => (l.uri ?? '').contains(hint),
      orElse: () => throw StateError('找不到库: $hint'),
    );
    targetLibId = lib.id!;
  }

  final resp = await service.callServiceExtension(
    'evaluate',
    isolateId: isolateId,
    args: {
      'targetId': targetLibId,
      'expression': expression,
      'disableBreakpoints': true,
    },
  );
  // 服务扩展返回的 JSON 里，成功时直接就是 Instance，失败时是 {error:...}。
  final json = resp.json;
  if (json == null) {
    print('RAW: null');
    await service.dispose();
    exit(1);
  }
  if (json['error'] != null) {
    print('ERROR: ${json['error']}');
    await service.dispose();
    exit(1);
  }
  final result = json.containsKey('kind') ? json : null;
  if (result == null) {
    print('RAW: ${jsonEncode(json)}');
    await service.dispose();
    exit(1);
  }
  if (result['kind'] == 'error') {
    final details = result['exceptionDetails'] as Map<String, dynamic>?;
    print('ERROR: ${details?['exceptionMessage'] ?? ''}');
    await service.dispose();
    exit(1);
  }

  // evaluate 返回的是 Instance 对象，值在 valueAsString 里。
  var value = result['valueAsString'] ?? result['value'] ?? '<null>';

  // 表达式返回 Future 时，等它跑完再取值。
  final className = ((result['class'] as Map?)?['name']) as String?;
  if (className != null && className.contains('Future')) {
    final objId = result['id'] as String?;
    value = await _awaitFuture(service, isolateId, objId!);
  }

  print(value);
  await service.dispose();
  exit(0);
}

/// 轮询 Future 的 _result / _error 字段，等它完成。
Future<String> _awaitFuture(
  VmService service,
  String isolateId,
  String objectId,
) async {
  for (var i = 0; i < 120; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final obj = await service.getObject(isolateId, objectId);
    final json = obj.json;
    // Future 完成后，VM service 会把结果挂在 _result / _error 上。
    final fields = (json?['fields'] as List?) ?? [];
    for (final f in fields) {
      final name = f['name'] as String?;
      // 字段的值在 f['value']['valueAsString']。
      final v = (f['value'] as Map?)?['valueAsString'] as String?;
      if (name == '_error' && v != null) {
        return 'FUTURE_ERROR: $v';
      }
      if (name == '_result' && v != null && v != 'null') {
        return v;
      }
    }
    // 有些情况下 VM service 直接把完成值放在 result 上。
    final direct = json?['result']?['valueAsString'];
    if (direct != null && direct != 'null') return direct as String;
    if (i == 119) {
      final names = fields
          .map((f) => '${f['name']}=${f['valueAsString'] ?? f['value']}')
          .join(' | ');
      stderr.writeln('DEBUG fields: $names');
    }
  }
  return 'FUTURE_TIMEOUT';
}
/// 把 http:// 的 VM service 地址转成 WebSocket 地址。
Uri _wsFromHttp(Uri uri) {
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return uri.replace(scheme: 'ws', path: '$path/ws');
}

/// 收集所有候选 VM service 地址（最新的排前面），并做端口转发。
Future<List<Uri>> _vmServiceCandidates(String adb) async {
  // logcat 会被冲掉，所以两处都找：logcat（App 自己打的）和
  // tool/run.dart 的输出日志（flutter 打的）。
  final texts = <String>[];

  final logcat = await Process.run(adb, ['logcat', '-d', '-v', 'brief']);
  texts.add(logcat.stdout.toString());

  File? runLog;
  for (final name in ['run_google.log', 'run_google2.log', 'run_google3.log']) {
    final f = File('build/$name');
    if (f.existsSync()) {
      runLog = f;
      break;
    }
  }
  if (runLog != null) texts.add(runLog.readAsStringSync());

  final pattern = RegExp(
    r'(?:Dart VM service is listening on|Dart VM Service on \S+ is available at:)\s*(http://127\.0\.0\.1:\d+/[^\s]+)',
  );

  final uris = <Uri>[];
  for (final text in texts) {
    for (final m in pattern.allMatches(text)) {
      final uri = Uri.parse(m.group(1)!);
      if (uris.any((u) => u.toString() == uri.toString())) continue;
      // 设备上的端口要转发到本机，VM service 只监听 127.0.0.1。
      await Process.run(adb, ['forward', 'tcp:${uri.port}', 'tcp:${uri.port}']);
      // VM service 的 WebSocket 端点 = 同一个路径再加 /ws。
      final path = uri.path.endsWith('/')
          ? uri.path.substring(0, uri.path.length - 1)
          : uri.path;
      uris.add(uri.replace(scheme: 'ws', path: '$path/ws'));
    }
  }
  // 最新的在后面，所以倒序返回。
  return uris.reversed.toList();
}

String? _adbPath() {
  final candidates = [
    '${Platform.environment['LOCALAPPDATA']}\\Android\\Sdk\\platform-tools\\adb.exe',
    '${Platform.environment['ANDROID_HOME'] ?? ''}\\platform-tools\\adb.exe',
    '${Platform.environment['ANDROID_SDK_ROOT'] ?? ''}\\platform-tools\\adb.exe',
  ];
  for (final c in candidates) {
    if (c.isNotEmpty && File(c).existsSync()) return c;
  }
  return null;
}
