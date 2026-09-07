import 'package:flutter/material.dart';

/// Stub used on non-web platforms. The web-only implementation lives in
/// `hai_pay_iframe_web.dart` and uses `HtmlElementView` + iframe. Callers
/// must guard with `kIsWeb` before instantiating this widget.
class HaiPayIframeWebView extends StatelessWidget {
  const HaiPayIframeWebView({
    super.key,
    required this.paymentUrl,
    this.onLoadFailed,
  });

  final String paymentUrl;
  final VoidCallback? onLoadFailed;

  @override
  Widget build(BuildContext context) {
    throw UnsupportedError(
      'HaiPayIframeWebView is only supported on the Web platform. '
      'Guard the call site with kIsWeb.',
    );
  }
}
