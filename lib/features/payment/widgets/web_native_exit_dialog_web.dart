import 'dart:html' as html;

import 'package:flutter/foundation.dart';

/// Web-only inline HTML dialog rendered as a real DOM element on top of any
/// `HtmlElementView` (iframe) inside the Flutter app.
///
/// Why this exists: Flutter's own Stack overlays are painted into a
/// `<flt-glass-pane>` that lives next to platform-view DOM nodes in the
/// same parent. Clicks inside the platform view (an iframe) never reach the
/// glass pane, so even a Flutter Stack child that *looks* like it sits on
/// top of the iframe cannot capture pointer events. Rendering a real
/// `<div>` directly into `document.body` with the maximum `z-index` is the
/// only reliable way to intercept clicks while the iframe is mounted.
@visibleForTesting
class WebNativeExitDialog {
  WebNativeExitDialog._();

  static html.Element? _root;

  static bool get isShowing => _root != null;

  static void show({
    required void Function() onStay,
    required void Function() onExit,
  }) {
    if (_root != null) return;

    final root = html.DivElement()
      ..id = 'web-native-exit-dialog'
      ..style.position = 'fixed'
      ..style.left = '0'
      ..style.top = '0'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.zIndex = '2147483647' // max possible z-index
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'center'
      ..style.backgroundColor = 'rgba(0, 0, 0, 0.55)';

    final card = html.DivElement()
      ..style.maxWidth = '360px'
      ..style.width = 'calc(100% - 48px)'
      ..style.backgroundColor = '#1F1A2E'
      ..style.border = '1px solid rgba(255, 255, 255, 0.12)'
      ..style.borderRadius = '16px'
      ..style.padding = '24px'
      ..style.boxShadow = '0 16px 48px rgba(0, 0, 0, 0.45)'
      ..style.fontFamily = 'system-ui, -apple-system, sans-serif'
      ..style.color = '#FFFFFF';

    final title = html.HeadingElement.h2()
      ..text = 'Exit Payment?'
      ..style.margin = '0 0 12px 0'
      ..style.fontSize = '18px'
      ..style.fontWeight = '600'
      ..style.textAlign = 'center';

    final body = html.ParagraphElement()
      ..text =
          'Are you sure you want to exit? If you have already completed '
          'payment, please wait a moment for confirmation.'
      ..style.margin = '0 0 20px 0'
      ..style.fontSize = '14px'
      ..style.lineHeight = '1.4'
      ..style.color = 'rgba(255, 255, 255, 0.7)'
      ..style.textAlign = 'center';

    final actions = html.DivElement()
      ..style.display = 'flex'
      ..style.justifyContent = 'flex-end'
      ..style.gap = '8px';

    final stayBtn = html.ButtonElement()
      ..text = 'Stay'
      ..style.padding = '10px 18px'
      ..style.background = 'transparent'
      ..style.color = 'rgba(255, 255, 255, 0.7)'
      ..style.border = 'none'
      ..style.borderRadius = '8px'
      ..style.fontSize = '14px'
      ..style.cursor = 'pointer';
    stayBtn.onClick.listen((_) {
      _dismiss();
      onStay();
    });

    final exitBtn = html.ButtonElement()
      ..text = 'Exit'
      ..style.padding = '10px 22px'
      ..style.background = '#7C5CFF'
      ..style.color = '#FFFFFF'
      ..style.border = 'none'
      ..style.borderRadius = '8px'
      ..style.fontSize = '14px'
      ..style.fontWeight = '500'
      ..style.cursor = 'pointer';
    exitBtn.onClick.listen((_) {
      _dismiss();
      onExit();
    });

    actions.children.addAll(<html.Element>[stayBtn, exitBtn]);
    card.children.addAll(<html.Element>[title, body, actions]);
    root.children.add(card);
    html.document.body!.append(root);
    _root = root;
  }

  static void _dismiss() {
    _root?.remove();
    _root = null;
  }

  static void dismiss() => _dismiss();
}
