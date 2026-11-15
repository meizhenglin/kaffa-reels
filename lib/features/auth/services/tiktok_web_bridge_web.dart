/// Web 端实现：浏览器弹窗 OAuth + postMessage 回传。
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'tiktok_web_message.dart';

export 'tiktok_web_message.dart';

/// Web 端 TikTok OAuth 浏览器桥。
class TiktokWebBridge {
  TiktokWebBridge._();

  static const String _messageSource = 'qahwa-tiktok-login';

  /// 打开授权弹窗并等待回调页 postMessage。
  ///
  /// 流程：`window.open(authorizeUrl)` → 用户在 TikTok 页面授权 →
  /// TikTok 302 到登记的 redirect_uri（静态回调页）→ 回调页把
  /// `code/state/error` 以 JSON 字符串 postMessage 回 opener 并自关。
  static Future<TiktokWebMessage> openPopupAndAwait(String authorizeUrl) async {
    final popup = html.window.open(
      authorizeUrl,
      'tiktok_oauth',
      'popup=yes,width=480,height=680',
    );
    if (popup == null) {
      // 浏览器拦截了弹窗（未给本站弹窗权限）。
      return const TiktokWebMessage(error: 'popup-blocked');
    }

    final completer = Completer<TiktokWebMessage>();
    late final StreamSubscription<html.MessageEvent> sub;
    late final Timer poll;

    sub = html.window.onMessage.listen((event) {
      if (completer.isCompleted) return;
      // 回调页发的是 JSON 字符串（跨 JS/Dart 边界传对象不可靠，传字符串最稳）。
      if (event.data is! String) return;
      final Map<String, dynamic> data;
      try {
        data = jsonDecode(event.data as String) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      if (data['source'] != _messageSource) return;
      completer.complete(
        TiktokWebMessage(
          code: data['code'] as String?,
          state: data['state'] as String?,
          error: data['error'] as String?,
        ),
      );
    });

    // 兜底：用户直接关掉弹窗（没走回调页的 postMessage）→ 视为取消。
    poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (completer.isCompleted) return;
      try {
        if (popup.closed == true) {
          completer.complete(const TiktokWebMessage(cancelled: true));
        }
      } catch (_) {}
    });

    final message = await completer.future;
    await sub.cancel();
    poll.cancel();
    try {
      popup.close();
    } catch (_) {}
    return message;
  }
}
