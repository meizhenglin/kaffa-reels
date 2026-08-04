import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../services/share_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../app/providers/app_providers.dart' show storageServiceProvider;

/// H5 游戏 WebView 页面
///
/// 【工作流程】
/// 1. 接收后端返回的游戏 H5 URL
/// 2. Flutter WebView 加载该 URL
/// 3. WebView 里 H5 引用 qahwa-jsapi.js，调用 adBreak() 展示激励广告
/// 4. MobileAds.registerWebView 让 adBreak() 自动路由到原生 AdMob
/// 5. 通过 JavaScriptChannel 处理登录/登出/充值回调
///
/// 【架构】
/// Flutter App
///     └── WebView 加载 游戏H5 URL
///             └── H5 引用 qahwa-jsapi.js
///                     └── H5 调用 QahwaJS.showAd() → adBreak() → AdMob ✅
class GameWebViewPage extends ConsumerStatefulWidget {
  const GameWebViewPage({
    super.key,
    required this.gameUrl,
    this.gameName,
  });

  static Future<void> show(
    BuildContext context, {
    required String gameUrl,
    String? gameName,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GameWebViewPage(
          gameUrl: gameUrl,
          gameName: gameName,
        ),
      ),
    );
  }

  final String gameUrl;
  final String? gameName;

  @override
  ConsumerState<GameWebViewPage> createState() => _GameWebViewPageState();
}

class _GameWebViewPageState extends ConsumerState<GameWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasRefreshedOnce = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    debugPrint('[GameWebView] gameUrl: ${widget.gameUrl}');

    // 如果是 Play Store 链接，直接用 url_launcher 打开
    if (_isPlayStoreUrl(widget.gameUrl)) {
      debugPrint('[GameWebView] Detected Play Store URL, opening with url_launcher');
      _openWithBrowser(widget.gameUrl);
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF2D2440));

    // 1. Android 启用第三方 cookie（AdMob H5 Games Ads 要求）
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewCookieManager(const PlatformWebViewCookieManagerCreationParams())
          .setAcceptThirdPartyCookies(platform, true);

      // 允许自动播放媒体
      platform.setMediaPlaybackRequiresUserGesture(false);
    }

    // 2. 设置 JavaScript Channel 处理 H5 回调
    _setupJavaScriptChannel();

    // 3. 设置导航监听
    _controller
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('[Game WebView] Loading: $progress%');
          },
          onPageStarted: (String url) {
            debugPrint('[Game WebView] Page started: $url');
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
          },
          onPageFinished: (String url) {
            debugPrint('[Game WebView] Page finished: $url');
            setState(() => _isLoading = false);

            // 页面加载完成后刷新一次，解决空白问题
            if (!_hasRefreshedOnce) {
              _hasRefreshedOnce = true;
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  _controller.reload();
                  debugPrint('[Game WebView] Auto-refresh after load');
                }
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('[Game WebView] Error: ${error.description}');
            setState(() {
              _isLoading = false;
              _errorMessage = error.description;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('[Game WebView] Navigation: ${request.url}');
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.gameUrl));

    // 4. 注册 MobileAds（在页面加载之后）
    _registerToMobileAds();
  }

  /// 判断是否是 Play Store URL
  bool _isPlayStoreUrl(String url) {
    return url.contains('play.google.com') ||
        url.contains('market.android.com');
  }

  /// 用系统浏览器打开 URL
  Future<void> _openWithBrowser(String url) async {
    setState(() => _isLoading = false);

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        debugPrint('[GameWebView] Opened in browser: $url');
        // 关闭 WebView 页面
        if (mounted) Navigator.of(context).pop();
      } else {
        setState(() => _errorMessage = 'Cannot open URL');
        debugPrint('[GameWebView] Cannot launch URL: $url');
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
      debugPrint('[GameWebView] Error opening URL: $e');
    }
  }

  /// 把 WebViewController 注册到 Google Mobile Ads SDK
  Future<void> _registerToMobileAds() async {
    try {
      await MobileAds.instance.registerWebView(_controller);
      debugPrint('[Game WebView] WebView registered to MobileAds SDK');
    } catch (e) {
      debugPrint('[Game WebView] Failed to register WebView to MobileAds: $e');
    }
  }

  /// 设置 JavaScript Channel 处理 H5 回调
  void _setupJavaScriptChannel() {
    _controller.addJavaScriptChannel(
      'QahwaNative',
      onMessageReceived: (JavaScriptMessage message) {
        _handleNativeCall(message.message);
      },
    );
  }

  /// 处理来自 H5 的调用
  void _handleNativeCall(String message) {
    debugPrint('[Game WebView] JS call: $message');

    try {
      final data = Map<String, dynamic>.from(
        Uri.splitQueryString(message).map(
          (key, value) => MapEntry(key, _parseJsonValue(value)),
        ),
      );

      final action = data['action'] as String? ?? '';
      final callbackId = data['callbackId'] as String? ?? '';

      switch (action) {
        case 'getUserInfo':
          _handleGetUserInfo(callbackId);
          break;
        case 'getToken':
          _handleGetToken(callbackId);
          break;
        case 'login':
          _handleLogin(callbackId);
          break;
        case 'logout':
          _handleLogout(callbackId);
          break;
        case 'recharge':
          _handleRecharge(data, callbackId);
          break;
        case 'share':
          _handleShare(data, callbackId);
          break;
        default:
          debugPrint('[Game WebView] Unknown action: $action');
      }
    } catch (e) {
      debugPrint('[Game WebView] Failed to handle message: $e');
    }
  }

  dynamic _parseJsonValue(String value) {
    if (value.isEmpty) return value;
    if ((value.startsWith('{') && value.endsWith('}')) ||
        (value.startsWith('[') && value.endsWith(']'))) {
      try {
        return value;
      } catch (_) {}
    }
    return value;
  }

  Future<void> _handleGetUserInfo(String callbackId) async {
    final authState = ref.read(authProvider);
    final user = authState.user;

    final result = {
      'success': user != null,
      if (user != null)
        'data': {
          'userId': user.id,
          'nickName': user.nickname ?? '',
          'email': user.email ?? '',
          'avatar': user.avatar ?? '',
        },
    };

    _evaluateJsCallback(callbackId, result);
  }

  Future<void> _handleGetToken(String callbackId) async {
    final storage = ref.read(storageServiceProvider);
    final token = await storage.getToken();

    final result = {
      'success': token != null && token.isNotEmpty,
      'token': token ?? '',
    };

    _evaluateJsCallback(callbackId, result);
  }

  void _handleLogin(String callbackId) {
    // 登录由 H5 自己处理（通过 QahwaJS.loginWithEmail 等方法）
    // 这里只提供登录状态的同步
    _handleGetUserInfo(callbackId);
  }

  void _handleLogout(String callbackId) {
    ref.read(authProvider.notifier).signOut();
    _evaluateJsCallback(callbackId, {'success': true});
  }

  void _handleRecharge(Map<String, dynamic> data, String callbackId) {
    final amount = double.tryParse(data['amount']?.toString() ?? '0') ?? 0;

    if (amount <= 0) {
      _evaluateJsCallback(callbackId, {
        'success': false,
        'error': 'Invalid amount',
      });
      return;
    }

    debugPrint('[Game WebView] Navigate to recharge page with amount: $amount');
    // TODO: 跳转到充值页面
    // Navigator.of(context).pop();

    _evaluateJsCallback(callbackId, {
      'success': true,
      'message': 'Redirecting to recharge page',
    });
  }

  void _handleShare(Map<String, dynamic> data, String callbackId) {
    final platform = data['platform'] as String? ?? '';
    final title = data['title'] as String? ?? '';
    final text = data['text'] as String? ?? '';
    final url = data['url'] as String? ?? '';
    final shareCallbackId = data['callbackId'] as String? ?? callbackId;

    if (platform.isEmpty || title.isEmpty) {
      _evaluateJsCallback(shareCallbackId, {
        'success': false,
        'error': 'platform and title are required',
      });
      return;
    }

    debugPrint('[Game WebView] Share: platform=$platform, title=$title, url=$url');

    try {
      ShareService.share(
        platformName: platform,
        title: title,
        text: text,
        url: url,
      );
      _evaluateJsCallback(shareCallbackId, {'success': true});
    } catch (e) {
      debugPrint('[Game WebView] Share failed: $e');
      _evaluateJsCallback(shareCallbackId, {
        'success': false,
        'error': e.toString(),
      });
    }
  }

  void _evaluateJsCallback(String callbackId, Map<String, dynamic> result) {
    final jsonStr = Uri.encodeComponent(result.toString());
    _controller.runJavaScript(
      'window.QahwaNative && window.QahwaNative._onCallback("$callbackId", $jsonStr);',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPlayStore = _isPlayStoreUrl(widget.gameUrl);

    return Scaffold(
      backgroundColor: const Color(0xFF2D2440),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2440),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.gameName ?? 'Game',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        centerTitle: true,
        actions: isPlayStore
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  onPressed: () => _controller.reload(),
                  tooltip: 'Reload',
                ),
              ],
      ),
      body: Stack(
        children: [
          if (isPlayStore)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white70),
                  SizedBox(height: 16),
                  Text(
                    'Opening in browser...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          else ...[
            // Loading indicator
            if (_isLoading)
              Container(
                color: const Color(0xFF2D2440),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Loading game...',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),

            // Error message
            if (_errorMessage != null)
              Container(
                color: const Color(0xFF2D2440),
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'Failed to load game',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => _controller.reload(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),

            // WebView
            if (!_isLoading && _errorMessage == null)
              Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ],
      ),
    );
  }
}
