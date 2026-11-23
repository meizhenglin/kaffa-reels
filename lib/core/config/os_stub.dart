/// dart:io 不可用（web）时的兜底实现。
class RuntimeOS {
  static bool get isIOS => false;
  static bool get isAndroid => false;
}
