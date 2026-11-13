/// Stub for native platform - games use native WebView
import 'package:flutter/widgets.dart';

class GameWebViewPage {
  static Future<void> show(
    BuildContext context, {
    required String gameUrl,
    String? gameName,
  }) async {
    throw UnimplementedError('GameWebViewPage not available on native');
  }
}
