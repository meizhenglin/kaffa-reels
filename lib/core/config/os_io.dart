import 'dart:io' show Platform;

/// dart:io 真实实现（只在支持 dart:io 的平台编译）。
class RuntimeOS {
  static bool get isIOS => Platform.isIOS;
  static bool get isAndroid => Platform.isAndroid;
}
