import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Renders [paymentUrl] inside an HTML <iframe> on the Web platform.
///
/// Limitations:
/// - Many payment providers set `X-Frame-Options: DENY` or
///   `Content-Security-Policy: frame-ancestors 'none'`. In that case the
///   iframe will fail to load and the UI exposes an "open in new tab"
///   fallback via the [onLoadFailed] callback so the caller can show a
///   link / use launchUrl instead.
/// - The iframe runs cross-origin by design, so we cannot read its DOM.
///   Payment status is polled via the backend like on native.
class HaiPayIframeWebView extends StatefulWidget {
  const HaiPayIframeWebView({
    super.key,
    required this.paymentUrl,
    this.onLoadFailed,
  });

  final String paymentUrl;
  final VoidCallback? onLoadFailed;

  @override
  State<HaiPayIframeWebView> createState() => _HaiPayIframeWebViewState();
}

class _HaiPayIframeWebViewState extends State<HaiPayIframeWebView> {
  late final String _viewType;
  html.IFrameElement? _iframe;

  @override
  void initState() {
    super.initState();
    _viewType =
        'haipay-webview-${widget.paymentUrl.hashCode}-${identityHashCode(this)}';
    _registerViewFactory();
  }

  void _registerViewFactory() {
    final url = widget.paymentUrl;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..src = url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allow = '';
        _iframe = iframe;
        iframe.onError.listen((_) {
          widget.onLoadFailed?.call();
        });
        return iframe;
      },
    );
  }

  @override
  void dispose() {
    _iframe?.remove();
    _iframe = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
