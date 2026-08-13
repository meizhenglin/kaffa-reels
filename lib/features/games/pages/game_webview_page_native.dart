import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/ads/ad_manager.dart';

/// Native 平台的 WebView 页面（支持 JS 广告调用）
class GameWebViewPage extends ConsumerStatefulWidget {
  const GameWebViewPage({
    super.key,
    required this.gameUrl,
    this.gameName,
  });

  final String gameUrl;
  final String? gameName;

  @override
  ConsumerState<GameWebViewPage> createState() => _GameWebViewPageState();
}

class _GameWebViewPageState extends ConsumerState<GameWebViewPage> {
  late WebViewController _controller;
  bool _isLoading = true;

  /// JS 调用方法的处理函数
  static const String _jsChannelName = 'QahwaAdChannel';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF2D2440))
      // 注册 JS Channel，用于接收 HTML 的广告请求
      ..addJavaScriptChannel(
        _jsChannelName,
        onMessageReceived: _handleJavaScriptMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              setState(() => _isLoading = false);
              // 页面加载完成后，注入 JS 广告桥接代码
              _injectAdBridge();
            }
          },
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.gameUrl));
  }

  /// 处理来自 JS 的消息
  void _handleJavaScriptMessage(JavaScriptMessage message) {
    debugPrint('[GameWebView] JS Message: ${message.message}');

    try {
      final data = Map<String, dynamic>.from(
        Uri.splitQueryString(message.message),
      );

      final action = data['action'] as String?;
      final callbackId = data['callbackId'] as String?;

      switch (action) {
        case 'showRewardedAd':
          _handleShowRewardedAd(callbackId);
          break;
        case 'showInterstitialAd':
          _handleShowInterstitialAd(callbackId);
          break;
        case 'checkAdReady':
          _handleCheckAdReady(callbackId, 'rewarded');
          break;
        default:
          debugPrint('[GameWebView] Unknown action: $action');
      }
    } catch (e) {
      debugPrint('[GameWebView] Error parsing JS message: $e');
    }
  }

  /// 显示激励广告
  Future<void> _handleShowRewardedAd(String? callbackId) async {
    debugPrint('[GameWebView] Showing rewarded ad...');

    final success = await AdManager.instance.showRewardedAd(
      onRewardEarned: () {
        // 广告看完，发放奖励
        debugPrint('[GameWebView] User earned reward');
        _sendResultToJs(callbackId, 'success', {'rewarded': true});
      },
      onNotReady: () {
        // 广告未就绪
        debugPrint('[GameWebView] Rewarded ad not ready');
        _sendResultToJs(callbackId, 'not_ready', {});
      },
    );

    if (!success) {
      // 广告显示失败
      _sendResultToJs(callbackId, 'failed', {});
    }
  }

  /// 显示插屏广告
  Future<void> _handleShowInterstitialAd(String? callbackId) async {
    debugPrint('[GameWebView] Showing interstitial ad...');

    final success = await AdManager.instance.showInterstitialAd();

    if (success) {
      _sendResultToJs(callbackId, 'success', {});
    } else {
      _sendResultToJs(callbackId, 'failed', {});
    }
  }

  /// 检查广告是否就绪
  void _handleCheckAdReady(String? callbackId, String adType) {
    final isReady = adType == 'rewarded'
        ? AdManager.instance.isRewardedAdReady()
        : true;

    _sendResultToJs(callbackId, 'ready', {'ready': isReady});
  }

  /// 向 JS 发送结果（通过 QahwaNative._onAdResult 回调）
  void _sendResultToJs(String? callbackId, String status, Map<String, dynamic> data) {
    if (callbackId == null || callbackId.isEmpty) return;

    final result = {
      'success': status == 'success',
      'dismissed': status == 'dismissed' || status == 'not_ready',
      'reason': status,
      ...data,
    };

    // 调用 QahwaNative._onAdResult（jsapi.js 期望的回调方式）
    final jsCode = 'if (window.QahwaNative && window.QahwaNative._onAdResult) { window.QahwaNative._onAdResult("$callbackId", ${jsonEncode(result)}); }';
    _controller.runJavaScript(jsCode);
  }

  /// 注入 JS 广告桥接代码
  Future<void> _injectAdBridge() async {
    // 注意：即使 window.QahwaNative 已存在（HTML 占位对象），也要覆盖它
    // 因为占位对象的 postMessage 是空实现，需要替换为真正的 Flutter 通信
    const bridgeCode = '''
      // Qahwa 广告桥接 - 用于在 WebView 中调用原生 AdMob 广告
      // 即使已存在占位对象，也要覆盖为真正的 Flutter 通信实现
      (function() {
        // 强制覆盖 window.QahwaNative（移除之前的占位检查）
        window.QahwaNative = {
          // 发送消息到 Flutter
          postMessage: function(msg) {
            try {
              var data = typeof msg === 'string' ? JSON.parse(msg) : msg;
              console.log('[QahwaNative] postMessage:', data);

              if (data.action === 'showRewardedAd' && data.requestId) {
                var requestId = data.requestId;

                // 调用 Flutter 的 QahwaAdChannel
                if (window.QahwaAdChannel) {
                  window.QahwaAdChannel.postMessage('action=showRewardedAd&requestId=' + requestId);
                }
              }
            } catch (e) {
              console.error('[QahwaNative] postMessage error:', e);
            }
          },

          // Flutter 广告结果回调 - 调用 QahwaJS 的 _handleAdCallback 方法
          _onAdResult: function(requestId, result) {
            console.log('[QahwaNative] _onAdResult called:', requestId, result);
            // 调用 QahwaJS 的回调处理方法（由 qahwa-jsapi.js 定义）
            if (window.QahwaJS && typeof window.QahwaJS._handleAdCallback === 'function') {
              window.QahwaJS._handleAdCallback(requestId, result);
            } else {
              console.error('[QahwaNative] QahwaJS._handleAdCallback not found!');
            }
          }
        };

        console.log('[Qahwa] QahwaNative bridge initialized (overriding placeholder)');
      })();
    ''';

    await _controller.runJavaScript(bridgeCode);
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
    );
  }
}

/// 打开游戏 WebView
Future<void> showWebView(
  BuildContext context, {
  required String gameUrl,
  String? gameName,
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
