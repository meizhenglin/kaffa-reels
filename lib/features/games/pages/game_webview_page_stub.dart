/// Stub for native platform - games use native WebView
class GameWebViewPage {
  static Future<void> show(
    BuildContext context, {
    required String gameUrl,
    String? gameName,
  }) async {
    throw UnimplementedError('GameWebViewPage not available on native');
  }
}
