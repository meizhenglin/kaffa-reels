import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

/// Web 平台的 WebView 页面 - 使用 iframe
class GameWebViewPage extends StatefulWidget {
  const GameWebViewPage({
    super.key,
    required this.gameUrl,
    this.gameName,
  });

  final String gameUrl;
  final String? gameName;

  @override
  State<GameWebViewPage> createState() => _GameWebViewPageState();
}

class _GameWebViewPageState extends State<GameWebViewPage> {
  late String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'game-webview-${widget.gameUrl.hashCode}';
    _registerViewFactory();
  }

  void _registerViewFactory() {
    final url = widget.gameUrl;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..src = url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
        return iframe;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2440),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2440),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.gameName ?? 'Game',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: HtmlElementView(viewType: _viewType),
    );
  }
}

/// 打开游戏 WebView (Web 平台)
Future<void> showWebView(
  BuildContext context, {
  required String gameUrl,
  String? gameName,
  int orientation = 1, // Web平台忽略此参数，仅为接口一致性
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      fullscreenDialog: true,
      pageBuilder: (context, animation, secondaryAnimation) => GameWebViewPage(
        gameUrl: gameUrl,
        gameName: gameName,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}
