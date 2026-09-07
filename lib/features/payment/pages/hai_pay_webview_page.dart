import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/hai_pay_models.dart';
import '../widgets/hai_pay_iframe_stub.dart'
    if (dart.library.html) '../widgets/hai_pay_iframe_web.dart' as iframe_impl;
import '../widgets/web_native_exit_dialog_stub.dart'
    if (dart.library.html) '../widgets/web_native_exit_dialog_web.dart'
    as web_dialog;
import '../services/hai_pay_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/storage_service.dart';

/// HaiPay H5 payment page
/// Mirrors Android's WebViewDefaultActivity
/// - Opens H5 payment page in WebView
/// - Polls payment status when app resumes
/// - Reports payment result back to backend
class HaiPayWebViewPage extends StatefulWidget {
  const HaiPayWebViewPage({
    super.key,
    required this.paymentUrl,
    required this.orderNo,
    required this.productType,
    required this.methodName,
    this.onPaymentComplete,
  });

  /// H5 payment URL from backend
  final String paymentUrl;

  /// Backend order number
  final String orderNo;

  /// "1" = VIP, "2" = recharge, "3" = episode unlock
  final String productType;

  /// Display name of the selected payment method
  final String methodName;

  /// Callback when payment is confirmed
  final void Function(bool success)? onPaymentComplete;

  static Future<bool?> show({
    required BuildContext context,
    required String paymentUrl,
    required String orderNo,
    required String productType,
    required String methodName,
    void Function(bool success)? onPaymentComplete,
  }) {
    debugPrint(
      '[HaiPayWebView] show paymentUrl=$paymentUrl orderNo=$orderNo productType=$productType methodName=$methodName',
    );
    // ignore: avoid_print
    print(
      '[HaiPayWebView] show paymentUrl=$paymentUrl orderNo=$orderNo productType=$productType methodName=$methodName',
    );
    return Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => HaiPayWebViewPage(
          paymentUrl: paymentUrl,
          orderNo: orderNo,
          productType: productType,
          methodName: methodName,
          onPaymentComplete: onPaymentComplete,
        ),
      ),
    );
  }

  @override
  State<HaiPayWebViewPage> createState() => _HaiPayWebViewPageState();
}

class _HaiPayWebViewPageState extends State<HaiPayWebViewPage>
    with WidgetsBindingObserver {
  WebViewController? _controller; // null on web
  final HaiPayService _haiPayService = HaiPayService(
    dioClient: DioClient(),
    storage: StorageService(),
  );

  bool _isLoading = true;
  bool _hasPaymentCompleted = false;
  bool _isCheckingClose = false;
  bool _isPolling = false;
  bool _iframeBlocked = false; // web-only: true when iframe can't embed
  bool _showExitDialog = false; // inline overlay (so it stacks above the web iframe)
  int _pollCount = 0;
  StreamSubscription<HaiPayStatus>? _pollSubscription;
  String? _lastErrorMessage;

  // Navigation delegate to track page loads
  NavigationDecision _handleNavigation(NavigationRequest request) {
    // Allow all navigation requests
    return NavigationDecision.navigate;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (kIsWeb) {
      _initWeb();
    } else {
      _initNative();
    }
  }

  Future<void> _initWeb() async {
    setState(() {
      _isLoading = true;
      _iframeBlocked = false;
    });
    // Start polling immediately — backend will report success regardless of
    // whether the user pays inside the iframe or in a new tab.
    _startPolling();
    // The iframe Has-Been-Loaded event isn't exposed through HtmlElementView,
    // so we just hide the spinner after a short delay. If the iframe can't
    // embed at all, _onIframeBlocked() (via the onError hook) will switch to
    // the fallback UI.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted || _iframeBlocked) return;
    setState(() => _isLoading = false);
  }

  void _onIframeBlocked() {
    if (!mounted || _iframeBlocked) return;
    debugPrint('[HaiPayWebView][Web] iframe blocked — fallback to new tab');
    setState(() {
      _iframeBlocked = true;
      _isLoading = false;
    });
  }

  void _initNative() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'CloseWebView',
        onMessageReceived: _handleCloseWebView,
      )
      ..setBackgroundColor(const Color(0xFF2D2440))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              setState(() => _isLoading = false);
            }
          },
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
            _installCloseWebViewBridge();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint(
              '[HaiPayWebView] WebResourceError: ${error.description}',
            );
          },
          onNavigationRequest: _handleNavigation,
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  Future<void> _installCloseWebViewBridge() async {
    if (_controller == null) return;
    // The payment H5 was originally written for flutter_inappwebview. Map its
    // close handler to webview_flutter's registered JavaScript channel.
    await _controller!.runJavaScript('''
      (function() {
        function closeFlutterWebView() {
          if (window.CloseWebView && window.CloseWebView.postMessage) {
            window.CloseWebView.postMessage('closeWebView');
          }
        }

        window.flutter_inappwebview = window.flutter_inappwebview || {};
        window.flutter_inappwebview.callHandler = function(name) {
          if (name === 'closeWebView') {
            closeFlutterWebView();
          }
        };

        // Also catch the payment page's inline Close link directly. This
        // keeps the close action working if the page replaces callHandler.
        if (!document.documentElement.dataset.flutterCloseBridgeInstalled) {
          document.documentElement.dataset.flutterCloseBridgeInstalled = 'true';
          document.addEventListener('click', function(event) {
            var target = event.target;
            var link = target && target.closest
                ? target.closest('a[onclick*="closeWebView"]')
                : null;
            if (link) {
              event.preventDefault();
              event.stopImmediatePropagation();
              closeFlutterWebView();
            }
          }, true);
        }
      })();
    ''');
  }

  Future<void> _handleCloseWebView(JavaScriptMessage message) async {
    if (message.message != 'closeWebView' || !mounted || _isCheckingClose) {
      return;
    }

    _isCheckingClose = true;
    // A Close control in the payment H5 is an explicit request to dismiss the
    // Flutter route. Do not wait for payment-status polling before closing.
    Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollSubscription?.cancel();
    if (kIsWeb) {
      web_dialog.WebNativeExitDialog.dismiss();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  void _onAppResumed() {
    // When app resumes (user returns from external payment app or completes payment),
    // start polling for payment status
    if (!_hasPaymentCompleted && !_isPolling) {
      _startPolling();
    }
  }

  Future<void> _startPolling() async {
    if (_isPolling) return;
    _isPolling = true;
    _pollCount = 0;

    debugPrint('[HaiPayWebView] Start polling for order: ${widget.orderNo}');

    _pollSubscription = _haiPayService
        .startPolling(
          type: widget.productType,
          orderNo: widget.orderNo,
          interval: const Duration(seconds: 2),
          timeout: const Duration(minutes: 3),
          maxAttempts: 30, // 30 * 2s = up to ~1 minute
        )
        .listen(
          (status) {
            _pollCount++;
            debugPrint(
              '[HaiPayWebView] Poll #$_pollCount: isPay=${status.isPay}',
            );

            if (status.isPaid) {
              _onPaymentConfirmed();
            }
            // Note: we intentionally do NOT auto-stop polling at 10 attempts.
            // On Flutter Web the user may keep the payment tab open in the
            // background for a while before completing it, so the spinner
            // should keep showing until the backend reports paid or the
            // stream exhausts its maxAttempts / timeout (handled by the
            // service). The user can always retry manually via the refresh
            // button.
          },
          onError: (error) {
            debugPrint('[HaiPayWebView] Poll error: $error');
            _stopPolling();
          },
          onDone: () {
            // Stream ended (timeout / maxAttempts / paid). Always sync UI.
            debugPrint('[HaiPayWebView] Polling stream done');
            _stopPolling();
          },
          cancelOnError: true,
        );
  }

  void _stopPolling() {
    _pollSubscription?.cancel();
    _pollSubscription = null;
    if (_isPolling) {
      _isPolling = false;
      if (mounted) setState(() {});
    }
  }

  void _onPaymentConfirmed() {
    if (_hasPaymentCompleted) return;
    _hasPaymentCompleted = true;
    _stopPolling();

    debugPrint('[HaiPayWebView] Payment confirmed!');

    if (kIsWeb) {
      web_dialog.WebNativeExitDialog.dismiss();
    }

    // Report payment result to backend
    _reportPaymentResult(isPay: '0').then((_) {
      if (mounted) {
        widget.onPaymentComplete?.call(true);
        Navigator.of(context).pop(true);
      }
    });
  }

  Future<void> _reportPaymentResult({required String isPay}) async {
    try {
      final storage = StorageService();
      final token = await storage.getToken();
      final dio = DioClient().dio;

      final time = DateTime.now().millisecondsSinceEpoch;
      final params = {
        'orderNo': widget.orderNo,
        'timeStamp': time.toString(),
        'status': isPay,
      };

      await dio.post(
        '/pay/paymentResult',
        data: params,
        options: Options(
          headers: {if (token != null && token.isNotEmpty) 'token': token},
        ),
      );

      debugPrint('[HaiPayWebView] Payment result reported: isPay=$isPay');
    } catch (e) {
      debugPrint('[HaiPayWebView] Failed to report payment result: $e');
    }
  }

  Future<void> _retryPaymentCheck() async {
    if (_isPolling) return;
    // One-shot status check first, then resume streaming polling if it
    // still hasn't been paid — gives the user immediate feedback on tap
    // instead of a silent flicker.
    final status = await _haiPayService.pollPaymentStatus(
      type: widget.productType,
      orderNo: widget.orderNo,
    );

    if (!mounted) return;

    if (status.isPaid) {
      _onPaymentConfirmed();
      return;
    }

    setState(() {
      _lastErrorMessage =
          'Payment not completed yet. Please complete payment first.';
    });
    // Resume streaming polling so the spinner keeps tracking the order.
    _startPolling();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2440),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2440),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => _showExitConfirmation(context),
        ),
        title: Text(
          widget.methodName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        actions: [
          if (_isPolling)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              onPressed: _retryPaymentCheck,
              tooltip: 'Retry payment check',
            ),
        ],
      ),
      body: kIsWeb ? _buildWebBody() : _buildNativeBody(),
    );
  }

  Widget _buildNativeBody() {
    return Stack(
      children: [
        if (_controller != null)
          WebViewWidget(controller: _controller!),
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
                    'Loading payment page...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        if (_lastErrorMessage != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 12 + MediaQuery.of(context).padding.bottom,
              ),
              color: Colors.red.withValues(alpha: 0.9),
              child: Text(
                _lastErrorMessage!,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (_showExitDialog) _buildExitOverlay(),
      ],
    );
  }

  Widget _buildWebBody() {
    if (_iframeBlocked) {
      return _buildWebFallbackBody();
    }
    return Stack(
      children: [
        Positioned.fill(
          child: iframe_impl.HaiPayIframeWebView(
            paymentUrl: widget.paymentUrl,
            onLoadFailed: _onIframeBlocked,
          ),
        ),
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
                    'Loading payment page...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        // Polling status is shown in the AppBar (see build()); we don't
        // duplicate the spinner + 'Checking...' label inside the page body
        // because on Flutter Web the floating overlay can sit awkwardly on
        // top of the H5 iframe's own controls.
        if (_lastErrorMessage != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 12 + MediaQuery.of(context).padding.bottom,
              ),
              color: Colors.red.withValues(alpha: 0.9),
              child: Text(
                _lastErrorMessage!,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (_showExitDialog) _buildExitOverlay(),
      ],
    );
  }

  Widget _buildWebFallbackBody() {
    return Container(
      color: const Color(0xFF2D2440),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.open_in_new,
              size: 64,
              color: Colors.white70,
            ),
            const SizedBox(height: 24),
            const Text(
              'Open payment page',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                'This payment page cannot be shown inside the app. '
                'Tap the button below to open it in a new browser tab, '
                'then return here. We will auto-detect when payment '
                'is complete.',
                style: const TextStyle(color: Colors.white60, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C5CFF),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.open_in_new, color: Colors.white),
              label: const Text(
                'Open payment page',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              onPressed: () async {
                final ok = await launchUrl(
                  Uri.parse(widget.paymentUrl),
                  mode: LaunchMode.externalApplication,
                );
                if (!ok && mounted) {
                  setState(() {
                    _lastErrorMessage =
                        'Could not open the payment page automatically. '
                        'Please copy this link manually:\n${widget.paymentUrl}';
                  });
                }
              },
            ),
            const SizedBox(height: 24),
            if (_isPolling)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Checking payment status...',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                textStyle: const TextStyle(fontSize: 14),
              ),
              onPressed: _retryPaymentCheck,
              child: const Text('Check payment status now'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExitConfirmation(BuildContext context) async {
    if (!mounted) return;
    _isCheckingClose = true;

    if (kIsWeb) {
      // On Flutter Web, Flutter Stack overlays cannot intercept pointer
      // events that fall inside a HtmlElementView (the payment iframe), so
      // we render the dialog as a real DOM element on top of <body>.
      web_dialog.WebNativeExitDialog.show(
        onStay: () {
          if (!mounted) return;
          setState(() => _isCheckingClose = false);
        },
        onExit: () {
          if (!mounted) return;
          _stopPolling();
          Navigator.of(context).pop(false);
        },
      );
      return;
    }

    setState(() => _showExitDialog = true);
  }

  void _onStayPressed() {
    if (!mounted) return;
    setState(() {
      _showExitDialog = false;
      _isCheckingClose = false;
    });
  }

  void _onExitPressed() {
    if (!mounted) return;
    _stopPolling();
    Navigator.of(context).pop(false);
  }

  /// Inline exit-confirmation overlay.
  ///
  /// We intentionally do NOT use `showDialog` here because on Flutter Web,
  /// pushing a new route floats a `ModalBarrier` *next to* the
  /// `HtmlElementView` (which renders the payment iframe). The barrier does
  /// not capture pointer events against the iframe stacking context, so
  /// clicks leak through to the iframe below. Rendering the dialog as the
  /// last child of the same `Stack` guarantees the barrier and buttons sit
  /// on top of the iframe in the same Flutter paint order.
  Widget _buildExitOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        // Swallow any tap that lands on the barrier itself.
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1A2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Exit Payment?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Are you sure you want to exit? If you have already '
                      'completed payment, please wait a moment for '
                      'confirmation.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _onStayPressed,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                          ),
                          child: const Text('Stay'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _onExitPressed,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF7C5CFF),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 10,
                            ),
                          ),
                          child: const Text(
                            'Exit',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
