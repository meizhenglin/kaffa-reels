/// 非 Web 端 stub：Web 浏览器桥不可用。
import 'tiktok_web_message.dart';

export 'tiktok_web_message.dart';

class TiktokWebBridge {
  TiktokWebBridge._();

  static Future<TiktokWebMessage> openPopupAndAwait(String authorizeUrl) async {
    throw UnsupportedError('TiktokWebBridge is only available on Flutter Web.');
  }
}
