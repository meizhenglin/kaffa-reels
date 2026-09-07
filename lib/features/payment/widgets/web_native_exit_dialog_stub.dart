/// Stub used on non-web platforms. The web-only implementation lives in
/// `web_native_exit_dialog_web.dart` and renders a real DOM dialog on top
/// of the Flutter iframe. Callers must guard with `kIsWeb` before calling.
class WebNativeExitDialog {
  WebNativeExitDialog._();

  static bool get isShowing => false;

  static void show({
    required void Function() onStay,
    required void Function() onExit,
  }) {
    throw UnsupportedError(
      'WebNativeExitDialog is only supported on the Web platform. '
      'Guard the call site with kIsWeb.',
    );
  }

  static void dismiss() {}
}
