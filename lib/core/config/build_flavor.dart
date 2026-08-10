/// Identifies which product flavor this binary was built for.
///
/// Set at build time via `--dart-define=FLAVOR=...`:
///   - "google"    : Google Play version. Only Google Play billing is
///                   enabled; HaiPay flow is disabled.
///   - "platform"  : Self-hosted platform version. Both HaiPay and
///                   Google Play flows are enabled (currently only
///                   HaiPay is wired up).
class BuildFlavor {
  // 平台默认值改为 platform，这样当没有显式指定时也能正常工作
  static const String _value =
      String.fromEnvironment('FLAVOR', defaultValue: 'platform');

  static const String google = 'google';
  static const String platform = 'platform';

  static const String current = _value;

  /// True when this binary is the Google Play build.
  static const bool isGoogle = _value == google;

  /// True when this binary is the self-hosted platform build.
  static const bool isPlatform = _value == platform;

  /// Human-readable name (for splash / debug overlays).
  static const String label = _value == platform ? 'Platform' : 'Google';

  /// App display name suffix (debug overlays only — Android uses gradle
  /// productFlavor resValue("string", "app_name", ...) for the launcher).
  static const String appNameSuffix = _value == platform ? ' (Platform)' : '';
}