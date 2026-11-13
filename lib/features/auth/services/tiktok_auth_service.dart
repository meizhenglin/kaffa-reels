import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/config/app_config.dart';
import '../../../app/router/router_config.dart' show rootNavigatorKey;
import '../exceptions/auth_exceptions.dart';

/// TikTok Login Kit OAuth authorization-code flow using an in-app WebView.
///
/// The app generates and validates `state`, intercepts the registered HTTPS
/// callback before navigation, then sends the authorization code and matching
/// redirect URI to the backend. The client secret stays on the backend.

/// 一次成功授权的产物。
class TiktokLoginResult {
  const TiktokLoginResult({
    required this.authCode,
    required this.redirectUri,
    this.codeVerifier,
  });

  /// TikTok 下发的授权码。
  final String authCode;

  /// 本次请求 code 时实际使用的 redirect URI。
  final String redirectUri;

  /// PKCE 的 `code_verifier`（未启用 PKCE 时为 null）。
  ///
  /// 【必须原样交给后端】后端用 code 换 access_token 时要带上它，且必须与
  /// 生成 `code_challenge` 时用的那个字符串**逐字节一致**，否则 TikTok 会
  /// 返回 `invalid_grant`。这个值只在本进程内存在，不需要持久化。
  final String? codeVerifier;
}

/// TikTok 登录业务异常。
class TiktokSignInException implements Exception {
  const TiktokSignInException(this.code, this.message);

  /// 机器可读的错误码（见 [TiktokAuthService] 内部各 onError 分支）。
  final String code;

  /// 人类可读的说明。
  final String message;

  @override
  String toString() => 'TiktokSignInException($code): $message';
}

/// TikTok 登录服务入口。
class TiktokAuthService {
  TiktokAuthService._();

  /// WebView OAuth is supported on Android and iOS only.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 发起登录并返回 TikTok authorization code。
  static Future<TiktokLoginResult> login() async {
    if (!isSupported) {
      throw const TiktokSignInException(
        'tiktok-platform-unsupported',
        'TikTok sign-in is only available on Android and iOS.',
      );
    }

    final state = _generateState();
    // PKCE 的 verifier 必须活到回调之后，因为后端换 token 时要用。
    final codeVerifier = AppConfig.tiktokUsePkce
        ? _generateCodeVerifier()
        : null;
    final codeChallenge = codeVerifier == null
        ? null
        : _codeChallengeS256(codeVerifier);

    final result = await TiktokLoginWebView.show(
      authorizeUrlBuilder: (redirectUri) =>
          _buildAuthorizeUrl(redirectUri, state, codeChallenge: codeChallenge),
      redirectUri: AppConfig.tiktokRedirectUri,
      expectedState: state,
    );

    return TiktokLoginResult(
      authCode: result.authCode,
      redirectUri: result.redirectUri,
      codeVerifier: codeVerifier,
    );
  }

  /// 清理 WebView cookies，便于用户登出后切换 TikTok 账号。
  static Future<void> clearWebViewState() async {
    if (!isSupported) return;
    try {
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // WKWebView 的 cookie 存在独立的 WKHTTPCookieStore 里，
        // 必须显式清一遍，否则下次仍会复用上一个账号的登录态。
        await WebStorageManager.instance().deleteAllData();
      }
    } catch (e) {
      debugPrint('[TiktokAuthService] clearCookies failed: $e');
    }
  }

  /// 16 字节随机数的 hex 串（32 字符）
  static String _generateState() {
    final r = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 生成 PKCE `code_verifier`（RFC 7636：43–128 个 unreserved 字符）。
  ///
  /// 48 字节随机数做 base64url 去 padding，得到 64 个字符，字符集正好是
  /// `A-Z a-z 0-9 - _`，全部落在 RFC 允许的 `unreserved` 范围内。
  static String _generateCodeVerifier() {
    final r = math.Random.secure();
    final bytes = List<int>.generate(48, (_) => r.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// 计算 PKCE challenge：**SHA-256 的小写十六进制**（64 个字符）。
  ///
  /// 【这里不能照抄标准 OAuth 实现】标准 PKCE（RFC 7636）要的是
  /// `base64url(sha256(verifier))`，而 TikTok 要的是十六进制。
  /// 用 base64url 得到的字符串长度和字符集都不对，换 token 时会被拒。
  static String _codeChallengeS256(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Build a TikTok OAuth authorization URL for the Web flow.
  ///
  /// 【严格对齐官方文档】TikTok Login Kit for Web 文档规定的必备参数只有 5 个：
  /// `client_key` / `scope` / `redirect_uri` / `state` / `response_type`，
  /// 端点为 `https://www.tiktok.com/v2/auth/authorize/`（**带**尾斜杠）。
  /// 另有一个可选参数 `disable_auto_auth`（0/1），本项目不使用。
  /// 文档还明确要求 `redirect_uri` 必须 https、绝对、静态、不含参数与 fragment。
  ///
  /// 【为什么这里刻意不传 `source`】
  /// 曾试过加 `source=web`（依据 TikTok 授权页 `authV2.js` 的 Web 分支会给
  /// 请求补上它），但实测在真实桌面 Chrome 中带与不带结果完全一致，
  /// 而文档也没列它。多传无文档依据的参数只会给排查增加噪音——
  /// 10002 的官方含义就是「请求里带了不支持的参数」。
  /// 详见 `docs/deployment/tiktok-diagnosis.md`。
  ///
  /// 【PKCE 由 [AppConfig.tiktokUsePkce] 控制，默认关闭】
  /// 文档的 Web 流没有 PKCE；TikTok 的 `authV2.js` 只在「来自原生 SDK」
  /// 和「redirect_uri 是 localhost/127.0.0.1（Desktop 流）」两个分支里写
  /// `code_challenge`。本项目回调是自建域名，属于 Web 流。
  /// 实现完整保留（见 [_generateCodeVerifier] / [_codeChallengeS256]），
  /// 开关一行即可启用；启用后 `code_verifier` 会自动透传给后端。
  static String _buildAuthorizeUrl(
    String redirectUri,
    String state, {
    String? codeChallenge,
  }) {
    return Uri.https('www.tiktok.com', '/v2/auth/authorize/', {
      'response_type': 'code',
      'client_key': AppConfig.tiktokClientKey,
      'scope': AppConfig.tiktokScope,
      'redirect_uri': redirectUri,
      'state': state,
      if (codeChallenge != null) ...{
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    }).toString();
  }
}

/// ============================================================================
/// 全屏 WebView 容器（Web 流授权页）。
/// ============================================================================
class TiktokLoginWebView {
  TiktokLoginWebView._();

  static Future<TiktokLoginResult> show({
    required String Function(String redirectUri) authorizeUrlBuilder,
    required String redirectUri,
    required String expectedState,
  }) async {
    final completer = Completer<TiktokLoginResult>();
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) {
      throw const TiktokSignInException(
        'tiktok-no-navigator',
        'App navigator not ready. Make sure rootNavigatorKey is set on MaterialApp.',
      );
    }

    bool popped = false;
    bool finished = false;
    void safePop() {
      if (popped) return;
      popped = true;
      final nav = rootNavigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.pop();
      }
    }

    late final Timer timer;
    String? lastNavigationUrl;

    void finish(void Function() deliver) {
      if (finished) return;
      finished = true;
      timer.cancel();
      safePop();
      deliver();
    }

    timer = Timer(AppConfig.tiktokLoginTimeout, () {
      finish(() {
        completer.completeError(
          TiktokSignInException(
            'tiktok-timeout',
            'TikTok login timed out. Last page: '
                '${lastNavigationUrl ?? 'not reported by WebView'}.',
          ),
        );
      });
    });

    await navigator.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _TiktokWebViewPage(
          authorizeUrlBuilder: authorizeUrlBuilder,
          redirectUri: redirectUri,
          expectedState: expectedState,
          onNavigationChanged: (url) {
            lastNavigationUrl = url;
          },
          onResult: (code, usedRedirectUri) {
            finish(() {
              completer.complete(
                TiktokLoginResult(authCode: code, redirectUri: usedRedirectUri),
              );
            });
          },
          onCancel: () {
            finish(() {
              completer.completeError(const AuthCancelledException());
            });
          },
          onSystemPop: () {
            if (finished) return;
            finished = true;
            popped = true;
            timer.cancel();
            completer.completeError(const AuthCancelledException());
          },
          onError: (code, msg) {
            finish(() {
              completer.completeError(TiktokSignInException(code, msg));
            });
          },
        ),
      ),
    );

    if (!finished) {
      finished = true;
      timer.cancel();
      completer.completeError(const AuthCancelledException());
    }

    return completer.future;
  }
}

/// 实际展示的 WebView 页面。
class _TiktokWebViewPage extends StatefulWidget {
  const _TiktokWebViewPage({
    required this.authorizeUrlBuilder,
    required this.redirectUri,
    required this.expectedState,
    required this.onNavigationChanged,
    required this.onResult,
    required this.onCancel,
    required this.onSystemPop,
    required this.onError,
  });

  final String Function(String redirectUri) authorizeUrlBuilder;
  final String redirectUri;
  final String expectedState;
  final ValueChanged<String> onNavigationChanged;
  final void Function(String code, String redirectUri) onResult;
  final VoidCallback onCancel;
  final VoidCallback onSystemPop;
  final void Function(String code, String msg) onError;

  @override
  State<_TiktokWebViewPage> createState() => _TiktokWebViewPageState();
}

class _TiktokWebViewPageState extends State<_TiktokWebViewPage> {
  InAppWebViewController? _controller;

  /// 当前打开的弹窗窗口 id（`window.open` / Google 登录弹窗）。
  ///
  /// 【为什么需要它】TikTok 登录页的 Google 按钮走 Google Identity Services
  /// 的弹窗流程：用户在弹窗里完成授权后，弹窗页面把凭据 `postMessage` 给
  /// `window.opener`，再自己 `window.close()`。单窗口 WebView 没有 opener，
  /// 于是流程永久停在 `accounts.google.com/gsi/transform` 白屏。
  /// 只有真正的多窗口 WebView（`onCreateWindow` + `InAppWebView(windowId:)`）
  /// 才有 opener，这段流程才能闭环。
  int? _popupWindowId;

  bool _processing = false;
  String? _lastNavigationUrl;

  /// 解析后的回调 URI（用于比对是不是命中了 redirect_uri）
  late final Uri _callbackUri;

  /// 与 [_callbackUri] 指向**同一个文档**的所有可接受路径。
  ///
  /// `https://host/dir/` 和 `https://host/dir/index.html` 在服务器上返回的
  /// 是同一个文件（nginx 的 index 指令），但 TikTok 回跳时用的是哪个，
  /// 取决于 Developer Portal 里登记的那一条**逐字节**字符串。
  ///
  /// 【为什么两种都要接受】只要登记值和 `AppConfig.tiktokRedirectUri`
  /// 有一个字符不同，回跳 URL 就不会命中拦截：WebView 会把回调页当普通
  /// 页面加载，用户看到一屏原始 JSON，App 一直等到 5 分钟超时才报错。
  /// 这种失败完全没有可读的错误信息，排查成本极高。
  late final Set<String> _acceptedCallbackPaths;

  /// WebView 设置。多窗口相关的三个开关是本次改造的核心：
  /// - `supportMultipleWindows`：允许 `window.open` 创建子窗口；
  /// - `javaScriptCanOpenWindowsAutomatically`：允许脚本在没有用户手势时
  ///   创建窗口，Google Identity Services 的弹窗属于这一类；
  /// - `useShouldOverrideUrlLoading`：让每次主框架跳转都先经过我们，
  ///   否则回调和 authorize 错误都拦不住。
  InAppWebViewSettings get _webViewSettings => InAppWebViewSettings(
    javaScriptEnabled: true,
    supportMultipleWindows: true,
    javaScriptCanOpenWindowsAutomatically: true,
    useShouldOverrideUrlLoading: true,
    mediaPlaybackRequiresUserGesture: false,
    // Google 授权页要读写 accounts.google.com 的 cookie，
    // 少这个开关会导致每次都要重新输账号密码。
    thirdPartyCookiesEnabled: true,
    sharedCookiesEnabled: true,
    domStorageEnabled: true,
    useWideViewPort: true,
    loadWithOverviewMode: true,
    // debug 下允许通过 chrome://inspect 附加，方便抓网络。
    isInspectable: kDebugMode,
  );

  @override
  void initState() {
    super.initState();
    _callbackUri = Uri.parse(widget.redirectUri);
    _acceptedCallbackPaths = _buildAcceptedCallbackPaths();
  }

  /// 诊断通道：把 WebView 里的 JSON 响应打到日志。
  ///
  /// `flutter_inappwebview` 的 JS 侧调用约定是
  /// `window.flutter_inappwebview.callHandler('TiktokDiag', ...)`，
  /// 与 `webview_flutter` 的 `TiktokDiag.postMessage` 不同。
  void _bindDiagnostics(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'TiktokDiag',
      callback: (args) {
        debugPrint('[TikTokDiag] ${args.join(' ')}');
        return null;
      },
    );
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _controller = controller;
    _bindDiagnostics(controller);
  }

  Future<NavigationActionPolicy> _onShouldOverride(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final url = action.request.url;
    if (url == null) return NavigationActionPolicy.ALLOW;
    final raw = url.toString();
    final uri = Uri.tryParse(raw);
    if (uri == null) return NavigationActionPolicy.ALLOW;

    // 弹窗创建时的初始文档是 about:blank，不能拦。
    if (uri.scheme == 'about') return NavigationActionPolicy.ALLOW;

    // 非 https（intent://、market://、tel:、自定义 scheme）一律拦掉：
    // 放行会跳出 WebView 或落到错误页，而我们无法处理它们的返回值。
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      debugPrint('[TiktokWebView] blocked navigation: scheme=${uri.scheme}');
      return NavigationActionPolicy.CANCEL;
    }

    // 【错误会被 TikTok 跳回 authorize 端点本身，必须在这里拦】
    // 服务端拒绝时不是跳回 redirect_uri，而是把 authorize URL 原地换成
    // `...&error=invalid_request&logid=...`。若只拦回调域名，这条跳转会被
    // 当成普通页面放行：WebView 显示 TikTok 的「出错了」页面，Dart 侧
    // 永远收不到错误，最后只能等 5 分钟超时。
    if (_isTikTokAuthorizeUrl(uri) &&
        uri.queryParameters.containsKey('error')) {
      return _handleUrl(raw);
    }

    // TikTok may navigate through login and CAPTCHA hosts outside
    // tiktok.com. Only the registered callback needs interception.
    if (_isCallbackUrl(uri)) return _handleUrl(raw);

    return NavigationActionPolicy.ALLOW;
  }

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    final raw = url?.toString();
    if (raw == null) return;
    _lastNavigationUrl = _safeUrlForLog(raw);
    widget.onNavigationChanged(_lastNavigationUrl!);
    debugPrint('[TiktokWebView] page started: $_lastNavigationUrl');
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    final raw = url?.toString();
    if (raw == null) return;
    _lastNavigationUrl = _safeUrlForLog(raw);
    widget.onNavigationChanged(_lastNavigationUrl!);
    debugPrint('[TiktokWebView] page finished: $_lastNavigationUrl');
  }

  /// 允许 WebView 真正创建一个子窗口。
  ///
  /// 返回 `true` 只表示「我要自己承载这个窗口」；真正渲染靠 build 里
  /// 那一层 `InAppWebView(windowId: popupWindowId)`。
  Future<bool> _onCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction action,
  ) async {
    debugPrint('[TiktokWebView] popup requested windowId=${action.windowId}');
    if (!mounted) return false;
    setState(() => _popupWindowId = action.windowId);
    return true;
  }

  void _closePopup() {
    if (_popupWindowId == null) return;
    if (!mounted) return;
    debugPrint('[TiktokWebView] popup closed');
    setState(() => _popupWindowId = null);
  }

  String _safeUrlForLog(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return '<invalid-url>';
    return uri.replace(query: null, fragment: null).toString();
  }

  /// 【诊断用】重放 TikTok 授权页自己调用的 `page/detail` 接口。
  ///
  /// 错误页只暴露 `error=invalid_request`，而真正的数字错误码
  /// （例如 `10002`）和 `error_description`（例如
  /// `The request parameters are malformed.`）只存在于这个接口的 JSON 响应里。
  /// 在 WebView 内部发起请求可以复用 `www.tiktok.com` 的同源上下文和 cookie，
  /// 避免 CORS 与风控判定差异，拿到与 TikTok 自己那次调用尽可能接近的结果。
  ///
  /// 仅在 debug 构建里执行，响应通过 `TiktokDiag` 通道打到日志。
  void _probePageDetail() {
    if (!kDebugMode) return;

    final payload = jsonEncode({
      'response_type': 'code',
      'client_key': AppConfig.tiktokClientKey,
      'scope': AppConfig.tiktokScope,
      'state': widget.expectedState,
      'redirect_uri': widget.redirectUri,
      'source': 'web',
      'locale': 'en',
      'auth_version': 'v2',
      'app_id': 1180,
    });

    final js = '''
(function(){
  function send(m){
    try { window.flutter_inappwebview.callHandler('TiktokDiag', m); } catch (e) {}
  }
  try {
    fetch('/tiktok/v2/oauth/page/detail/?locale=en', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: ${jsonEncode(payload)}
    }).then(function(r){ return r.text(); })
      .then(function(t){ send('PAGE_DETAIL ' + t); })
      .catch(function(e){ send('PAGE_DETAIL_ERR ' + e); });
  } catch (e) {
    send('PAGE_DETAIL_THROW ' + e);
  }
})();
''';

    _controller?.evaluateJavascript(source: js);
  }

  /// Handle navigation and intercept OAuth callbacks before loading them.
  NavigationActionPolicy _handleUrl(String urlStr) {
    if (_processing) return NavigationActionPolicy.CANCEL;

    Uri u;
    try {
      u = Uri.parse(urlStr);
    } catch (_) {
      return NavigationActionPolicy.ALLOW;
    }

    // Handle OAuth errors on the authorization endpoint.
    if (_isTikTokAuthorizeUrl(u)) {
      final errorValues = u.queryParametersAll['error'] ?? const <String>[];
      final errorParam = errorValues.length == 1 ? errorValues.single : null;
      if (errorParam != null && errorParam.isNotEmpty) {
        final errCode = u.queryParameters['errCode'] ?? '';
        final errType = u.queryParameters['error_type'] ?? '';
        final errDesc = u.queryParameters['error_description'] ?? '';
        final logId =
            u.queryParameters['logid'] ??
            u.queryParameters['log_id'] ??
            u.queryParameters['logId'] ??
            '';

        debugPrint(
          '[TiktokWebView] authorize error=$errorParam '
          'errCode=$errCode error_type=$errType '
          'description=$errDesc logid=$logId',
        );

        _probePageDetail();

        _processing = true;
        void report() {
          widget.onError(
            _authorizeErrorCode(errorParam, errCode, errType),
            _authorizeErrorMessage(
              errorParam: errorParam,
              errCode: errCode,
              errType: errType,
              logId: logId,
              description: errDesc,
            ),
          );
        }

        if (kDebugMode) {
          // 先让上面那条 page/detail 诊断请求跑完再关闭页面，
          // 否则 WebView 被销毁、响应永远打不出来。
          Future<void>.delayed(const Duration(milliseconds: 1500), report);
        } else {
          report();
        }
        return NavigationActionPolicy.CANCEL;
      }
    }

    // Intercept TikTok authorize errors before checking the redirect URI.
    if (_isCallbackUrl(u)) {
      final codeValues = u.queryParametersAll['code'] ?? const <String>[];
      final stateValues = u.queryParametersAll['state'] ?? const <String>[];
      final errorValues = u.queryParametersAll['error'] ?? const <String>[];
      final code = codeValues.length == 1 ? codeValues.single : null;
      final returnedState = stateValues.length == 1 ? stateValues.single : null;
      final err = errorValues.length == 1 ? errorValues.single : null;

      // 【官方文档定义的 error_description】
      // TikTok 文档明确：`error` 一旦出现，含义是「当前用户不具备使用第三方
      // 登录/授权的资格」，而 `error_description` 是配套的人类可读说明。
      // 这个字段此前被丢弃，等于扔掉了唯一的诊断线索。
      final errDesc = u.queryParameters['error_description'] ?? '';
      final errLogId =
          u.queryParameters['logid'] ??
          u.queryParameters['log_id'] ??
          u.queryParameters['logId'] ??
          '';

      if (err != null && err.isNotEmpty) {
        debugPrint(
          '[TiktokWebView] callback returned error=$err '
          'description=$errDesc logid=$errLogId',
        );
        _processing = true;
        final errorCode = _authorizeErrorCode(err, '', '');
        if (errorCode == 'tiktok-access-denied') {
          widget.onCancel();
        } else {
          widget.onError(
            errorCode,
            _authorizeErrorMessage(
              errorParam: err,
              errCode: '',
              errType: '',
              logId: errLogId,
              description: errDesc,
            ),
          );
        }
        return NavigationActionPolicy.CANCEL;
      }

      // Require a fresh state value before accepting the authorization code.
      if (returnedState == null || returnedState != widget.expectedState) {
        debugPrint('[TiktokWebView] callback state mismatch or missing');
        _processing = true;
        widget.onError(
          'tiktok-state-mismatch',
          'OAuth state parameter is missing or does not match. Please try again.',
        );
        return NavigationActionPolicy.CANCEL;
      }

      if (code == null || code.isEmpty) {
        debugPrint('[TiktokWebView] callback without authorization code');
        _processing = true;
        widget.onError(
          'tiktok-missing-auth-code',
          'TikTok redirected back to the callback URL without an '
              'authorization code.',
        );
        return NavigationActionPolicy.CANCEL;
      }

      debugPrint(
        '[TiktokWebView] authorization code received (len=${code.length})',
      );
      _processing = true;
      widget.onResult(code, widget.redirectUri);
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }

  /// Match the registered HTTPS callback origin and path.
  bool _isCallbackUrl(Uri u) {
    final actualPath = u.path.isEmpty ? '/' : u.path;
    return u.scheme == 'https' &&
        u.host.toLowerCase() == _callbackUri.host.toLowerCase() &&
        u.port == _callbackUri.port &&
        u.userInfo.isEmpty &&
        _acceptedCallbackPaths.contains(actualPath);
  }

  /// `/dir/` 与 `/dir/index.html` 视为同一个回调地址。
  Set<String> _buildAcceptedCallbackPaths() {
    final basePath = _callbackUri.path.isEmpty ? '/' : _callbackUri.path;
    return <String>{
      basePath,
      if (basePath.endsWith('/')) '${basePath}index.html',
      if (basePath.endsWith('/index.html'))
        basePath.substring(0, basePath.length - 'index.html'.length),
    };
  }

  bool _isTikTokAuthorizeUrl(Uri uri) {
    if (!_isTikTokUrl(uri)) return false;
    // 官方文档的端点是 `/v2/auth/authorize/`（带尾斜杠），但 TikTok 自己
    // 在错误跳转里可能省略它；两种都认，避免又漏拦。
    final path = uri.path;
    return path == '/v2/auth/authorize/' || path == '/v2/auth/authorize';
  }

  bool _isTikTokUrl(Uri uri) {
    return uri.scheme == 'https' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        _isTikTokHost(uri.host);
  }

  bool _isTikTokHost(String host) {
    final normalizedHost = host.toLowerCase();
    return normalizedHost == 'tiktok.com' ||
        normalizedHost.endsWith('.tiktok.com');
  }

  /// Map TikTok authorization errors to stable app error codes.
  static String _authorizeErrorCode(
    String errorParam,
    String errCode,
    String errType,
  ) {
    // 服务端直接给了数字错误码 → 用它细分
    if (errCode.isNotEmpty) {
      if (errType == 'client_key') return 'tiktok-invalid-client-key';
      if (errType == 'scope') return 'tiktok-invalid-scope';
      if (errType == 'redirect_uri') return 'tiktok-redirect-uri-mismatch';
      return 'tiktok-authorize-code-refused';
    }
    switch (errorParam) {
      case 'invalid_request':
        // TikTok 只回 `error=invalid_request`，既不带 errCode 也不带
        // error_type，说明它连「参数级」的细分都没给出。
        // 已知可能来源：Login Kit → Web 产品未开启/未生效、应用未通过审核、
        // 登录账号不在 Sandbox Target User 名单里，或 redirect_uri 与 Portal
        // 登记值不一致。这些都不是客户端能自证的，必须让用户拿到 logid
        // 去找 TikTok 支持，所以单独给一个错误码。
        return 'tiktok-app-product-not-enabled';
      case 'unauthorized_client':
        return 'tiktok-invalid-client-key';
      case 'invalid_scope':
        return 'tiktok-invalid-scope';
      case 'access_denied':
        return 'tiktok-access-denied';
      case 'server_error':
        return 'tiktok-server-error';
      default:
        return 'tiktok-authorize-rejected';
    }
  }

  /// Format an authorization error for the user. Credentials are never included.
  ///
  /// [description] 是 TikTok 的 `error_description`。官方文档对 `error` 的定义是
  /// 「当前用户不具备使用第三方登录/授权的资格」，`error_description` 则是配套的
  /// 人类可读说明 —— 这是定位原因最直接的字段，必须透出给用户和日志。
  static String _authorizeErrorMessage({
    required String errorParam,
    required String errCode,
    required String errType,
    required String logId,
    String description = '',
  }) {
    final buffer = StringBuffer()
      ..write(
        'TikTok refused to issue an authorization code '
        '(error=$errorParam',
      );
    if (errCode.isNotEmpty) buffer.write(', errCode=$errCode');
    if (errType.isNotEmpty) buffer.write(', error_type=$errType');
    buffer.write(')');

    if (description.isNotEmpty) buffer.write(' — $description');
    if (logId.isNotEmpty) buffer.write(' logid=$logId');

    buffer.write(
      '. TikTok did not return a specific error code. Verify in TikTok '
      'Developer Portal that Login Kit → Web is enabled and approved, that '
      'the redirect URI matches byte for byte, and — if the app is in '
      'Staging/Sandbox — that the signed-in account is a Target User.',
    );
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final popupWindowId = _popupWindowId;
    return PopScope(
      // 弹窗打开时，返回键先关弹窗，而不是直接退出整个登录流程。
      canPop: popupWindowId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closePopup();
          return;
        }
        widget.onSystemPop();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(widget.authorizeUrlBuilder(widget.redirectUri)),
                ),
                initialSettings: _webViewSettings,
                onWebViewCreated: _onWebViewCreated,
                shouldOverrideUrlLoading: _onShouldOverride,
                onCreateWindow: _onCreateWindow,
                onCloseWindow: (controller) => _closePopup(),
                onLoadStart: _onLoadStart,
                onLoadStop: _onLoadStop,
                onReceivedHttpError: (controller, request, errorResponse) {
                  debugPrint(
                    '[TiktokWebView] HTTP status ${errorResponse.statusCode}',
                  );
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame ?? true) {
                    debugPrint(
                      '[TiktokWebView] main-frame error '
                      'type=${error.type} description=${error.description}',
                    );
                  }
                },
              ),
              // 弹窗层：Google 登录等 `window.open` 出来的子窗口。
              if (popupWindowId != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.white,
                    child: InAppWebView(
                      key: ValueKey<int>(popupWindowId),
                      windowId: popupWindowId,
                      initialSettings: _webViewSettings,
                      onWebViewCreated: _bindDiagnostics,
                      shouldOverrideUrlLoading: _onShouldOverride,
                      onCreateWindow: _onCreateWindow,
                      onCloseWindow: (controller) => _closePopup(),
                      onLoadStart: _onLoadStart,
                      onLoadStop: _onLoadStop,
                    ),
                  ),
                ),
              // 关闭按钮
              Positioned(
                top: 8,
                left: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.onCancel,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}