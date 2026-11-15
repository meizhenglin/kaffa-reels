/// TikTok Web 端 OAuth 浏览器桥（条件导出）。
///
/// Web 端走 `dart:html` 实现（弹窗 + postMessage）；非 Web 端走 stub 抛异常。
export 'tiktok_web_bridge_stub.dart'
    if (dart.library.html) 'tiktok_web_bridge_web.dart';
