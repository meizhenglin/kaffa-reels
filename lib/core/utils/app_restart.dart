import 'dart:io';

import 'package:flutter/services.dart';

/// 应用重启工具
///
/// 通过 MethodChannel 调用 Android 原生方法实现真正的冷启动重启，
/// 确保 Flutter 引擎完全重新初始化，RTL 方向等全局状态正确生效。
class AppRestart {
  static const _channel = MethodChannel('com.video.qahwatvshort/restart');

  /// 重启应用（冷启动）
  static Future<void> restart() async {
    try {
      await _channel.invokeMethod('restart');
      // 如果原生调用没杀掉进程，等待一小段时间后 fallback
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (_) {}

    // Fallback：强制退出，下次启动就是冷启动
    try {
      exit(0);
    } catch (_) {
      await SystemNavigator.pop();
    }
  }
}
