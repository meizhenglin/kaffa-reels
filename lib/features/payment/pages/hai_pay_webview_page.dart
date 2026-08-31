import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/hai_pay_models.dart';
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
  late final WebViewController _controller;
  final HaiPayService _haiPayService = HaiPayService(
    dioClient: DioClient(),
    storage: StorageService(),
  );

  bool _isLoading = true;
  bool _hasPaymentCompleted = false;
  bool _isCheckingClose = false;
  bool _isPolling = false;
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
    // The payment H5 was originally written for flutter_inappwebview. Map its
    // close handler to webview_flutter's registered JavaScript channel.
    await _controller.runJavaScript('''
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
          timeout: const Duration(minutes: 15),
        )
        .listen(
          (status) {
            _pollCount++;
            debugPrint(
              '[HaiPayWebView] Poll #$_pollCount: isPay=${status.isPay}',
            );

            if (status.isPaid) {
              _onPaymentConfirmed();
            } else if (_pollCount >= 10) {
              // After ~20 seconds, stop auto-polling
              // User can manually retry by switching apps
              _stopPolling();
            }
          },
          onError: (error) {
            debugPrint('[HaiPayWebView] Poll error: $error');
            _stopPolling();
          },
        );
  }

  void _stopPolling() {
    _pollSubscription?.cancel();
    _pollSubscription = null;
    _isPolling = false;
  }

  void _onPaymentConfirmed() {
    if (_hasPaymentCompleted) return;
    _hasPaymentCompleted = true;
    _stopPolling();

    debugPrint('[HaiPayWebView] Payment confirmed!');

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
    final status = await _haiPayService.pollPaymentStatus(
      type: widget.productType,
      orderNo: widget.orderNo,
    );

    if (status.isPaid) {
      _onPaymentConfirmed();
    } else {
      setState(() {
        _lastErrorMessage =
            'Payment not completed yet. Please complete payment first.';
      });
    }
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
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
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
        ],
      ),
    );
  }

  Future<void> _showExitConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit Payment?'),
        content: const Text(
          'Are you sure you want to exit? If you have already completed payment, '
          'please wait a moment for confirmation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      Navigator.of(this.context).pop(false);
    }
  }
}
