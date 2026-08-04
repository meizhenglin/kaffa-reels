import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../pages/game_webview_page.dart';

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

    if (gameType.toLowerCase() == 'app') {
      // APP 游戏：提示下载
      _showDownloadDialog(context, l10n, gameName, downloadUrl);
    } else {
      // H5 游戏：使用 Flutter WebView 打开（支持 MobileAds.registerWebView）
      await _openH5Game(context, gameUrl, gameName);
    }
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
    debugPrint('[GameService] Download: $downloadUrl');
  }

  /// 打开 H5 游戏
  /// 使用 Flutter WebView 加载游戏 URL，以便：
  /// 1. 支持 MobileAds.registerWebView，让 H5 的 adBreak() 走 AdMob
  /// 2. 通过 JavaScriptChannel 处理登录/登出/充值回调
  static Future<void> _openH5Game(
    BuildContext context,
    String? gameUrl,
    String gameName,
  ) async {
    debugPrint('[GameService] _openH5Game called');
    debugPrint('[GameService] gameUrl: $gameUrl');
    debugPrint('[GameService] gameName: $gameName');

    if (gameUrl == null || gameUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game URL is empty')),
      );
      return;
    }

    await GameWebViewPage.show(
      context,
      gameUrl: gameUrl,
      gameName: gameName,
    );
  }
}
