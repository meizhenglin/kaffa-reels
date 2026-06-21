import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';

class GameService {
  /// 打开游戏
  static Future<void> openGame(
    BuildContext context,
    String gameType,
    String? gameUrl,
    String? downloadUrl,
    String gameName,
  ) async {
    final l10n = AppLocalizations.of(context);

    if (gameType.toLowerCase() == 'app') {
      // APP 游戏：提示下载
      _showDownloadDialog(context, l10n, gameName, downloadUrl);
    } else {
      // H5 游戏：直接打开
      await _openH5Game(context, l10n, gameUrl);
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
    final uri = Uri.parse(downloadUrl);
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open download link: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 打开 H5 游戏
  static Future<void> _openH5Game(
    BuildContext context,
    AppLocalizations l10n,
    String? gameUrl,
  ) async {
    if (gameUrl == null || gameUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.networkError),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final uri = Uri.parse(gameUrl);
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.inAppWebView,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.error}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
