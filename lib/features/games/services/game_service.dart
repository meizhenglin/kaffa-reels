import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../pages/game_webview_page_native.dart'
    if (dart.library.html) '../pages/game_webview_page_web.dart' as platform;

/// 统一的游戏 WebView 页面
class GameWebViewPage {
  static Future<void> show(
    BuildContext context, {
    required String gameUrl,
    String? gameName,
  }) {
    return platform.showWebView(context, gameUrl: gameUrl, gameName: gameName);
  }
}

class GameService {
  /// 打开游戏
  static Future<void> openGame(
    BuildContext context, {
    required String gameType,
    required String? gameUrl,
    String? downloadUrl,
    required String gameName,
  }) async {
    final l10n = AppLocalizations.of(context);

    if (kIsWeb) {
      await _openInBrowser(context, gameUrl, gameName);
      return;
    }

    if (gameType.toLowerCase() == 'app') {
      _showDownloadDialog(context, l10n, gameName, downloadUrl);
    } else {
      await _openH5Game(context, gameUrl, gameName);
    }
  }

  /// Web 端：在应用内打开游戏链接
  static Future<void> _openInBrowser(
    BuildContext context,
    String? gameUrl,
    String gameName,
  ) async {
    if (gameUrl == null || gameUrl.isEmpty) return;

    try {
      await GameWebViewPage.show(
        context,
        gameUrl: gameUrl,
        gameName: gameName,
      );
    } catch (_) {}
  }

  /// 显示下载提示对话框
  static void _showDownloadDialog(
    BuildContext context,
    AppLocalizations l10n,
    String gameName,
    String? downloadUrl,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.download, color: Colors.blue),
            const SizedBox(width: 8),
            Text(gameName),
          ],
        ),
        content: const Text(
          'This game requires download. Please download and install to play.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              if (downloadUrl != null && downloadUrl.isNotEmpty) {
                _downloadGame(context, downloadUrl);
              }
            },
            icon: const Icon(Icons.download),
            label: const Text('Download'),
          ),
        ],
      ),
    );
  }

  /// 下载游戏
  static Future<void> _downloadGame(BuildContext context, String downloadUrl) async {
    // TODO: 实现下载逻辑
  }

  /// 打开 H5 游戏
  static Future<void> _openH5Game(
    BuildContext context,
    String? gameUrl,
    String gameName,
  ) async {
    if (gameUrl == null || gameUrl.isEmpty) return;

    try {
      await platform.showWebView(
        context,
        gameUrl: gameUrl,
        gameName: gameName,
      );
    } catch (_) {}
  }
}
