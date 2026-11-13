import 'package:flutter_test/flutter_test.dart';
import 'package:qahwa_tv/core/config/app_config.dart';
import 'package:qahwa_tv/core/config/app_version.dart';
import 'package:qahwa_tv/core/config/build_flavor.dart';
import 'package:qahwa_tv/core/config/build_info.dart';
import 'package:qahwa_tv/core/network/x_client_header.dart';

/// 版本号与渠道标识的单元测试。
///
/// 运行时通过 dart-define 注入渠道与版本：
///   flutter test --dart-define=APP_VERSION=1.0.6 \
///                --dart-define=APP_BUILD_NUMBER=15 \
///                --dart-define=FLAVOR=google
void main() {
  test('渠道短码与渠道名一一对应', () {
    final expected = switch (BuildFlavor.current) {
      'google' => 'g',
      'platform' => 'p',
      'web' => 'w',
      _ => fail('未知渠道：${BuildFlavor.current}'),
    };
    expect(BuildFlavor.shortCode, expected);
  });

  test('displayVersion 由「版本号 + 渠道短码」拼成', () {
    expect(
      BuildInfo.displayVersion,
      '${BuildInfo.baseVersion}-${BuildFlavor.shortCode}',
    );
  });

  test('fullVersion 形如 1.0.6+15.p', () {
    expect(
      BuildInfo.fullVersion,
      '${BuildInfo.baseVersion}+${BuildInfo.buildNumber}'
      '.${BuildFlavor.shortCode}',
    );
  });

  test('注入了 dart-define 时 hasVersion 为 true', () {
    expect(BuildInfo.hasVersion, isTrue);
    expect(BuildInfo.baseVersion, isNot('0.0.0'));
  });

  test('渠道与渠道标签一致', () {
    if (BuildFlavor.isGoogle) {
      expect(BuildFlavor.label, 'Google');
    } else if (BuildFlavor.isPlatform) {
      expect(BuildFlavor.label, 'Platform');
    } else if (BuildFlavor.isWeb) {
      expect(BuildFlavor.label, 'Web');
    } else {
      fail('未知渠道：${BuildFlavor.current}');
    }
  });

  test('请求头里的 version 跟随 pubspec，不写死', () async {
    // AppVersion.resolveBase() 是 X-Client 请求头里 version= 的值。
    // 它必须和设置页显示的版本号同源，否则后端拿到的客户端版本
    // 跟用户实际装的包对不上。
    //
    // 跟 BuildInfo.baseVersion（即注入进来的 APP_VERSION）比：
    // 如果哪里写死了版本号，换个 dart-define 这条就会挂。
    expect(await AppVersion.resolveBase(), BuildInfo.baseVersion);
  });

  test('兜底版本号是合法版本号，不是 0.0.0', () {
    expect(AppConfig.fallbackVersion, matches(RegExp(r'^\d+\.\d+\.\d+')));
  });

  test('X-Client 头同时带上 version / channel / build', () async {
    // 之前 dio_client 那份头少了 channel 和 build，而它又是最后写
    // options.headers['X-Client'] 的那个 —— 实际发出去的从来都是
    // 少两个字段的那份。这条测试守住统一后的格式。
    final header = await XClientHeader.build(savedLang: 'ar');
    expect(header, contains('version=${BuildInfo.baseVersion}'));
    expect(header, contains('channel=${BuildFlavor.current}'));
    expect(header, contains('build=${BuildInfo.fullVersion}'));
    expect(header, contains('x-lang=ar-SA'));
  });

  test('X-Client 头的语言归一化', () {
    expect(XClientHeader.normalizeLang('ar'), 'ar-SA');
    expect(XClientHeader.normalizeLang('en'), 'en-US');
    expect(XClientHeader.normalizeLang('ar-SA'), 'ar-SA');
    expect(XClientHeader.normalizeLang(null), isNotEmpty);
  });

  test('没有 dart-define 时也能拿到合法版本号', () async {
    // Android Studio 直接 Run 的场景：没有 dart-define，
    // 靠 package_info_plus 读原生 versionName；读不到就退回兜底常量。
    final base = await AppVersion.resolveBase();
    final full = await AppVersion.resolveFull();
    expect(base, matches(RegExp(r'^\d+\.\d+\.\d+')));
    expect(full, isNotEmpty);
  });
}
