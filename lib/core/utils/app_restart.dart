import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 应用重启工具
///
/// 通过 MethodChannel 调用 Android 原生方法实现真正的冷启动重启，
/// 确保 Flutter 引擎完全重新初始化，RTL 方向等全局状态正确生效。
///
/// 【iOS】系统不允许 App 自行退出后再自动拉起（exit(0) 的表现就是
/// 用户看到的「闪退」）。iOS 改为「软重启」：注册回调重建整个
/// ProviderScope 子树（main.dart），所有 provider 状态归零、路由回
/// 初始页；进程级单例（Firebase / 广告 SDK）保持已初始化状态。
class AppRestart {
  /// iOS 软重启回调（main.dart 启动时注册）
  static Future<void> Function()? _softRestartCallback;

  /// main.dart 启动时注册 iOS 软重启实现
  static void registerSoftRestart(Future<void> Function() callback) {
    _softRestartCallback = callback;
  }

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

    // iOS：软重启（重建 provider 子树），绝不 exit(0) —— 否则表现就是闪退。
    final soft = _softRestartCallback;
    if (soft != null) {
      await soft();
      return;
    }
    // 兜底：回调未注册时退回导航复位，而不是杀进程。
    await SystemNavigator.pop();
  }
}
