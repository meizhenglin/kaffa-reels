import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/ads/ad_manager.dart';

/// Native 平台的 WebView 页面（支持 JS 广告调用）
class GameWebViewPage extends ConsumerStatefulWidget {
  const GameWebViewPage({
    super.key,
    required this.gameUrl,
    this.gameName,
    this.orientation = 0, // 0=横屏, 1=竖屏
  });

  final String gameUrl;
  final String? gameName;
  final int orientation; // 0=横屏, 1=竖屏

  @override
  ConsumerState<GameWebViewPage> createState() => _GameWebViewPageState();
}

class _GameWebViewPageState extends ConsumerState<GameWebViewPage> {
  late WebViewController _controller;
  bool _isLoading = true;
  late int _orientation;

  /// JS 调用方法的处理函数
  static const String _jsChannelName = 'QahwaAdChannel';

  @override
  void initState() {
    super.initState();
    debugPrint('[GameWebView] initState called, widget.orientation=${widget.orientation}');
    _orientation = widget.orientation;
    
    // 立即设置方向
    _setScreenOrientation();
    
    _initWebView();
  }

  /// 根据游戏方向设置屏幕方向
  void _setScreenOrientation() {
    debugPrint('[GameWebView] _setScreenOrientation called, orientation=$_orientation');
    if (Platform.isAndroid) {
      // 清空方向缓存
      SystemChrome.setPreferredOrientations([]);
      
      if (_orientation == 0) {
        // 横屏游戏：锁定横屏 + 沉浸模式
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        // 竖屏游戏：锁定竖屏
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    }
  }

  /// 恢复默认屏幕方向（页面退出时）
  @override
  void dispose() {
    debugPrint('[GameWebView] Disposing, restoring system UI...');
    // 强制显示状态栏和导航栏
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
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
      Map<String, dynamic> data;

      // 尝试解析 JSON 格式
      final msg = message.message.trim();
      if (msg.startsWith('{')) {
        data = Map<String, dynamic>.from(jsonDecode(msg));
      } else {
        // 解析 query string 格式
        data = Map<String, dynamic>.from(
          Uri.splitQueryString(msg),
        );
      }

      final action = data['action'] as String?;
      // SDK 使用 requestId，兼容旧桥接使用的 callbackId。
      final callbackId = (data['callbackId'] ?? data['requestId']) as String?;

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
        case 'setOrientation':
          _handleSetOrientation(data);
          break;
        default:
          debugPrint('[GameWebView] Unknown action: $action');
      }
    } catch (e) {
      debugPrint('[GameWebView] Error parsing JS message: $e');
    }
  }

  /// 处理 JS 设置屏幕方向
  void _handleSetOrientation(Map<String, dynamic> data) {
    final orientation = data['orientation'] as int?;
    if (orientation == null) return;

    debugPrint('[GameWebView] Setting orientation from JS: ${orientation == 0 ? "landscape" : "portrait"}');

    setState(() {
      _orientation = orientation;
    });

    if (Platform.isAndroid) {
      if (orientation == 0) {
        // 横屏游戏：沉浸模式
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        // 竖屏游戏：显示系统UI
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    }
  }

  /// 广告关闭后恢复屏幕方向
  void _handleRestoreOrientation() {
    debugPrint('[GameWebView] Restoring orientation after ad...');

    if (Platform.isAndroid) {
      if (_orientation == 0) {
        // 横屏游戏：沉浸模式
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        // 竖屏游戏：显示系统UI
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    }

    // 强制重建 UI
    setState(() {});
  }

  /// 显示激励广告
  Future<void> _handleShowRewardedAd(String? callbackId) async {
    debugPrint('[GameWebView] Showing rewarded ad...');

    // 隐藏 WebView（暂停游戏和音频）
    await _hideWebView();

    // 广告显示中，等待完成后恢复方向
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

    // 恢复 WebView 显示
    await _showWebView();
    
    // 广告关闭后恢复屏幕方向
    _handleRestoreOrientation();

    if (!success) {
      // 广告显示失败
      _sendResultToJs(callbackId, 'failed', {});
    }
  }

  /// 显示插屏广告
  Future<void> _handleShowInterstitialAd(String? callbackId) async {
    debugPrint('[GameWebView] Showing interstitial ad...');

    // 隐藏 WebView（暂停游戏和音频）
    await _hideWebView();

    // 广告显示中，等待完成后恢复方向
    final success = await AdManager.instance.showInterstitialAd();
    
    // 恢复 WebView 显示
    await _showWebView();
    
    _handleRestoreOrientation();

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

  /// 暂停游戏音频
  Future<void> _pauseGameAudio() async {
    await _controller.runJavaScript('''
      try {
        // 暂停所有音频元素
        var audios = document.querySelectorAll('audio');
        audios.forEach(function(audio) { audio.pause(); });
        
        // 尝试暂停视频
        var videos = document.querySelectorAll('video');
        videos.forEach(function(video) { video.pause(); });
        
        // 尝试暂停 Construct 2 引擎
        if (typeof cr !== 'undefined' && cr.plugins_ && cr.plugins_.Audio) {
          cr.plugins_.Audio.prototype.Pause.call(this);
        }
        
        // 降低页面音量
        if (typeof document !== 'undefined') {
          document.body.style.opacity = '0.5';
        }
        
        console.log('[GameWebView] Game audio paused');
      } catch (e) {
        console.log('[GameWebView] Pause audio error:', e);
      }
    ''');
  }

  /// 恢复游戏音频
  Future<void> _resumeGameAudio() async {
    await _controller.runJavaScript('''
      try {
        // 恢复所有音频元素
        var audios = document.querySelectorAll('audio');
        audios.forEach(function(audio) { audio.play(); });
        
        // 尝试恢复视频
        var videos = document.querySelectorAll('video');
        videos.forEach(function(video) { video.play(); });
        
        // 尝试恢复 Construct 2 引擎
        if (typeof cr !== 'undefined' && cr.plugins_ && cr.plugins_.Audio) {
          cr.plugins_.Audio.prototype.Resume.call(this);
        }
        
        // 恢复页面音量
        if (typeof document !== 'undefined') {
          document.body.style.opacity = '1';
        }
        
        console.log('[GameWebView] Game audio resumed');
      } catch (e) {
        console.log('[GameWebView] Resume audio error:', e);
      }
    ''');
  }

  /// 隐藏 WebView（广告显示时）
  Future<void> _hideWebView() async {
    await _controller.runJavaScript('''
      try {
        // 暂停所有音频元素
        var audios = document.querySelectorAll('audio');
        audios.forEach(function(audio) { audio.pause(); });
        
        // 暂停视频
        var videos = document.querySelectorAll('video');
        videos.forEach(function(video) { video.pause(); });
        
        // 隐藏 canvas
        var canvas = document.querySelector('canvas');
        if (canvas) canvas.style.display = 'none';
        
        // 隐藏游戏容器
        var canvasDiv = document.getElementById('c2canvasdiv');
        if (canvasDiv) canvasDiv.style.display = 'none';
        
        console.log('[GameWebView] WebView hidden');
      } catch (e) {
        console.log('[GameWebView] Hide WebView error:', e);
      }
    ''');
  }

  /// 显示 WebView（广告关闭后）
  Future<void> _showWebView() async {
    await _controller.runJavaScript('''
      try {
        // 显示 canvas
        var canvas = document.querySelector('canvas');
        if (canvas) canvas.style.display = 'block';
        
        // 显示游戏容器
        var canvasDiv = document.getElementById('c2canvasdiv');
        if (canvasDiv) canvasDiv.style.display = 'block';
        
        console.log('[GameWebView] WebView shown');
      } catch (e) {
        console.log('[GameWebView] Show WebView error:', e);
      }
    ''');
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

              if ((data.action === 'showRewardedAd' || data.action === 'showInterstitialAd') && data.requestId) {
                var requestId = data.requestId;
                var action = data.action;

                // 调用 Flutter 的 QahwaAdChannel
                if (window.QahwaAdChannel) {
                  window.QahwaAdChannel.postMessage('action=' + action + '&requestId=' + requestId);
                }
              } else if (data.action === 'setOrientation') {
                // 屏幕方向设置 - 直接通过 QahwaAdChannel 发送 JSON
                if (window.QahwaAdChannel) {
                  window.QahwaAdChannel.postMessage(JSON.stringify(data));
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

        // 桥接注入后，通知游戏当前方向（因为 init 时可能消息丢失了）
        if (window.QahwaJS && typeof window.QahwaJS._notifyOrientation === 'function') {
          console.log('[Qahwa] Re-notifying orientation after bridge init');
          window.QahwaJS._notifyOrientation();
        }
        
        // 同时，直接读取 QahwaJS._orientation 并通知 Flutter
        if (window.QahwaJS && typeof window.QahwaJS._orientation === 'number') {
          console.log('[Qahwa] Direct orientation sync: ' + window.QahwaJS._orientation);
          if (window.QahwaAdChannel) {
            window.QahwaAdChannel.postMessage(JSON.stringify({
              action: 'setOrientation',
              orientation: window.QahwaJS._orientation
            }));
          }
        }
      })();
    ''';

    await _controller.runJavaScript(bridgeCode);
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    // 横屏时：全屏 WebView
    if (_orientation == 0) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 全屏 WebView
            WebViewWidget(controller: _controller),
            // 状态栏背景（透明占位）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: topPadding,
                color: const Color(0xFF2D2440).withValues(alpha: 0.8),
              ),
            ),
            // 按钮行
            Positioned(
              top: topPadding + 8,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.refresh, color: Colors.white, size: 20),
                    ),
                    onPressed: () => _controller.reload(),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
          ],
        ),
      );
    }

    // 竖屏时：原布局
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 状态栏背景
          Container(
            width: double.infinity,
            height: topPadding,
            color: const Color(0xFF2D2440),
          ),
          // 游戏内容 + 按钮
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                // 按钮行
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.refresh, color: Colors.white, size: 20),
                          ),
                          onPressed: () => _controller.reload(),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 打开游戏 WebView
///
/// [orientation] 屏幕方向: 0=横屏, 1=竖屏
Future<void> showWebView(
  BuildContext context, {
  required String gameUrl,
  String? gameName,
  int orientation = 1, // 默认竖屏
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      fullscreenDialog: true,
      pageBuilder: (context, animation, secondaryAnimation) => GameWebViewPage(
        gameUrl: gameUrl,
        gameName: gameName,
        orientation: orientation,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}
