import 'dart:ui' show Locale, PlatformDispatcher;

import '../../app/providers/app_providers.dart';
import '../config/app_config.dart';
import '../config/app_version.dart';
import '../config/build_flavor.dart';

/// `X-Client` 请求头 —— **全项目唯一的构造入口**。
///
/// 【为什么要单独抽出来】
/// 之前 `api_service.dart` 和 `dio_client.dart` 各写了一份构造逻辑，
/// 而且两份**内容不一样**：
///
/// | 文件 | 格式 |
/// |---|---|
/// | `api_service.dart` | `...;version=1.0.6;...;channel=platform;build=1.0.6+15.p` |
/// | `dio_client.dart` | `...;version=1.0.6;...` ← **没有 channel / build** |
///
/// 而 Dio 的执行顺序是：先合并 `Options.headers`，**再**跑拦截器。
/// `dio_client` 的拦截器无条件写 `options.headers['X-Client']`，所以
/// 最终发出去的一直是它那份 —— `channel` 和 `build` 两个字段
/// **根本没到过后端**。
///
/// 统一到这里之后，格式固定为：
///
/// ```
/// platformId=2;platformAppId=2002;version=1.0.6;osName=Android;
/// x-lang=ar-SA;channel=platform;build=1.0.6+15.p
/// ```
class XClientHeader {
  XClientHeader._();

  /// 构造 `X-Client` 请求头的值。
  ///
  /// [savedLang] 是本地存储里保存的语言代码；为空时按 [fallbackLocale]
  /// （没给就用设备语言）兜底。
  static Future<String> build({
    required String? savedLang,
    Locale? fallbackLocale,
  }) async {
    final lang = normalizeLang(savedLang, fallbackLocale: fallbackLocale);
    final version = await AppVersion.resolveBase();
    final build = await AppVersion.resolveFull();
    return '${AppConfig.currentXClient};version=$version;'
        'osName=${AppConfig.platformType};x-lang=$lang;'
        'channel=${BuildFlavor.current};build=$build';
  }

  /// 语言归一化：`ar` → `ar-SA`，`en` → `en-US`，
  /// 都不是就按设备语言（[fallbackLocale]，没给就读系统语言）兜底。
  static String normalizeLang(String? value, {Locale? fallbackLocale}) {
    final normalized = value?.trim();
    if (normalized == 'ar-SA') return 'ar-SA';
    if (normalized == 'en-US') return 'en-US';
    if (normalized == 'ar') return 'ar-SA';
    if (normalized == 'en') return 'en-US';
    try {
      final locale = fallbackLocale ?? PlatformDispatcher.instance.locale;
      return formatDeviceLang(locale);
    } catch (_) {
      return 'en-US';
    }
  }
}
