import 'package:flutter/foundation.dart';

import 'os_stub.dart'
    if (dart.library.io) 'os_io.dart';

/// 运行时 OS 名称。
///
/// 【为什么不用 AppConfig.platformType】那是打包前手改的常量（Android/iOS），
/// 忘改会让 iOS 端拿到 Android 的 payType=5、请求头 osName=Android，
/// 订单渠道全记错。这里用条件导入隔离 dart:io（web 构建安全）。
///
/// 【web 返回 'Android'】保持与旧行为一致（AppConfig.platformType 旧值），
/// 避免 web 端 H5 支付的行为变化。
String get runtimeOsName {
  if (kIsWeb) return 'Android';
  return RuntimeOS.isIOS ? 'iOS' : 'Android';
}
