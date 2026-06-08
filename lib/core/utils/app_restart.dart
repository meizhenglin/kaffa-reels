import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 应用重启工具
///
/// 通过 MethodChannel 调用 Android 原生方法实现真正的冷启动重启，
/// 确保 Flutter 引擎完全重新初始化，RTL 方向等全局状态正确生效。
class AppRestart {
  static const _channel = MethodChannel('com.video.storydrama/restart');

  /// 重启应用（冷启动）
  static Future<void> restart() async {
    if (kIsWeb) {
      return;
    }

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('restart');
        return;
      } catch (_) {
        try {
          await SystemNavigator.pop();
          return;
        } catch (_) {
          exit(0);
        }
      }
    }

    try {
      exit(0);
    } catch (_) {
      await SystemNavigator.pop();
    }
  }
}
