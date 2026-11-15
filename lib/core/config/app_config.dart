/// ============================================================================
/// 应用配置文件
///
/// 【功能说明】
/// 对应小程序原版 config.js，定义 API 地址、平台标识、X-Client 信息等。
///
/// 【如何修改】
/// - 切换环境：修改 _apiBaseUrl
/// - 切换平台：修改当前使用的 X-Client 字符串（Android/iOS）
/// - 版本更新：修改 pubspec.yaml 里的 version（不要改这里）
/// ============================================================================
library;
  
class AppConfig {
  AppConfig._();

  // ==================== API 配置 ====================
  /// 正式环境 API 地址（私有常量）
  static const String apiBaseUrl = 'https://tvapi.qahwatv.com/';

  // test 环境 API 地址
  // static const String apiBaseUrl ="http://101.46.59.160:8082/";

  // 开发环境
  // static const String apiBaseUrl = 'http://192.168.1.51:8082/';

  // 打包产出包名带版本号的命令
  // 三条是独立的，各自产出到 build/artifacts/
  // dart tool\build.dart platform --release --split-per-abi
  // dart tool\build.dart google   --release --split-per-abi
  // dart tool\build.dart web       --release

  // dart tool\build.dart platform --debug

  // dart tool\build.dart google --debug --split-per-abi

  // dart tool\build.dart web --debug

// dart tool\build.dart google   --release --appbundle --version-code=2017
// dart tool\build.dart platform --release --appbundle --version-code=2017


// 运行到手机上调试的命令
// # Google Play 版
// dart tool\run.dart google

// # 自建平台版（Kaffa Reels）
// dart tool\run.dart platform


// # 默认 debug，约 130 MB，有热重载
// dart tool\run.dart platform
// dart tool\run.dart google

// # release，约 40 MB，没有热重载
// dart tool\run.dart platform --release
// dart tool\run.dart google --release


  /// 如需切回联调环境，可临时使用：
  /// https://scolding-unbaked-refrain.ngrok-free.dev/
  ///
  /// https://tvapi.qahwatv.com/
  ///
  ///
  ///
  ///
  /// # Google Play 版（只有 Google 支付）
  // flutter run --flavor google -t lib/main.dart --dart-define=FLAVOR=google
  // flutter build apk --flavor google -t lib/main.dart --dart-define=FLAVOR=google --release

  // # 自主平台版（只有 HaiPay）
  // flutter run --flavor platform -t lib/main.dart --dart-define=FLAVOR=platform
  // flutter build apk --flavor platform -t lib/main.dart --dart-define=FLAVOR=platform --release

  // 用途	命令
  // Platform debug 分包（刚跑）
  // flutter build apk --flavor platform -t lib/main.dart --dart-define=FLAVOR=platform --debug --split-per-abi
  // Google debug 分包
  // flutter build apk --flavor google -t lib/main.dart --dart-define=FLAVOR=google --debug --split-per-abi
  // Platform release 分包
  // flutter build apk --flavor platform -t lib/main.dart --dart-define=FLAVOR=platform --release --split-per-abi
  // Platform release 不分包（fat apk）
  // flutter build apk --flavor platform -t lib/main.dart --dart-define=FLAVOR=platform --release
  // google release 分包
  // flutter build apk --flavor google -t lib/main.dart --dart-define=FLAVOR=google --release --split-per-abi
  // google release 不分包（fat apk）
  // flutter build apk --flavor google -t lib/main.dart --dart-define=FLAVOR=google --release

  // flutter run --flavor platform --debug
  // flutter build apk --flavor platform --release --no-tree-shake-icons --split-per-abi

  // flutter run --flavor google --debug
  // flutter build apk --flavor google --release --no-tree-shake-icons --split-per-abi

  // # Google flavor
  // flutter run --flavor google --dart-define=FLAVOR=google --debug

  // # Platform flavor
  // flutter run --flavor platform --dart-define=FLAVOR=platform --debug

  // # web版本打包
  // flutter build web --base-href=/qahwa/

  // flutter build apk --flavor platform --dart-define=FLAVOR=platform --release --no-tree-shake-icons --split-per-abi

  /// 图片 CDN 地址
  // static const String picRootPath = 'https://image.qahwatv.com/';

  // ==================== 平台标识 ====================
  /// platformId=3;platformAppId=3001  抖音
  /// platformId=2;platformAppId=2001  微信
  /// platformId=2;platformAppId=2002  Android

  /// 越南 Android 平台标识
  static const String androidXClient = 'platformId=2;platformAppId=2002';

  /// 越南 iOS 平台标识
  static const String iOSXClient = 'platformId=3;platformAppId=3001';

  /// 当前平台 X-Client（根据运行平台切换）
  /// 【发布前】Android 打包时改为 androidXClient
  /// 【发布前】iOS 打包时改为 iOSXClient
  static String get currentXClient => androidXClient;

  // ==================== 版本号 ====================
  // ⚠️ 这里**不要**再写版本号。
  //
  // 版本号的唯一真相源是 `pubspec.yaml` 第 5 行的 `version:`，
  // 它同时决定：
  //   - 设置页显示的版本号
  //   - APK / AAB 原生的 versionName 和 versionCode
  //   - 请求头 `X-Client` 里的 `version=` 和 `build=`
  //
  // 取值逻辑在 `AppVersion`（lib/core/config/app_version.dart），
  // 它按「dart-define → 原生 versionName → 本常量」的顺序取，
  // 保证各处看到的版本号永远一致。

  /// 最后的兜底版本号。
  ///
  /// 只有在前两级（dart-define、原生 versionName）都拿不到时才会用，
  /// 正常情况下不会走到这里。写一个合法值即可，不需要跟着发版改 ——
  /// 真走到这一步说明安装包本身有问题，报上去比静默出错好。
  static const String fallbackVersion = '1.1.1';

  /// Android 资源包版本号（热更新用）
  static const String androidResourceVersion = '1.0.0';

  /// iOS 资源包版本号（热更新用）
  static const String iOSResourceVersion = '1.0.0';

  /// 当前资源包版本号
  static String get resourceVersion => androidResourceVersion;

  // ==================== 支付类型 ====================
  /// Android 支付标识
  static const int payTypeAndroid = 5;

  /// iOS 支付标识
  static const int payTypeiOS = 6;

  // ==================== 当前环境 ====================
  /// 当前平台类型（Android / iOS）
  /// 【发布前】根据打包平台修改此值
  static const String platformType = 'Android';

  // ==================== 客服配置 ====================
  /// 客服 IM ID（与平台标识同步修改）
  static const String imId = '';

  /// TikTok Web OAuth configuration. The client secret is server-side only.
  ///
  /// 【两个应用，用 [tiktokUseSandbox] 切换】
  /// 保留两个常量而不是直接改字符串，是为了让 A/B 变成一次布尔翻转，
  /// 不必在两串 key 之间来回粘贴、也不会漏改某处。
  static const String _tiktokClientKeyProduction = 'awy65nxalrzf8a76';
  static const String _tiktokClientKeySandbox = 'sbaw17e7imyq8yhdd2';

  /// 【诊断开关】`true` → 用沙盒应用，`false` → 用生产应用。
  ///
  /// 用途：生产应用的 authorize 一直返回 `error_code 10002`
  /// （`fatal_item_ids` 为空，任何参数都无法改变结果），换一个全新的
  /// client_key 可以判定「是这一个应用的服务端绑定坏了」还是
  /// 「账号/环境层面就过不去」。
  ///
  /// 【沙盒要能用，三件事缺一不可】
  /// 1. 沙盒应用的 Login Kit → Web 也登记同一条 redirect URI；
  /// 2. 沙盒应用里加上 `user.info.basic` 这个 scope；
  /// 3. 你用来登录的 TikTok 账号必须被加进沙盒的 **Target Users** —— 少了这步，
  ///    沙盒必然失败，且报错和现在这个一模一样，容易被误判成本项目的问题。
  ///
  /// 【只测授权页就能得出结论】客户端只把 `code` 交给后端，不带 client_key，
  /// 后端持有自己那份 key/secret。所以沙盒能否走到「授权同意页 / 回调带回
  /// code」这一步，与后端无关；要真正完成登录才需要后端同步换成沙盒的
  /// key + secret。
  ///
  /// ⚠️ 发版前必须改回 `false`。
  static const bool tiktokUseSandbox = false;

  /// 当前生效的 client key（由 [tiktokUseSandbox] 决定）。
  static String get tiktokClientKey =>
      tiktokUseSandbox ? _tiktokClientKeySandbox : _tiktokClientKeyProduction;
  static const String tiktokScope = 'user.info.basic';

  /// 【必须与 Portal 登记的字符串逐字节一致】
  /// TikTok 换 token 时也会带这个值做比对，多一个 `index.html`、少一个尾斜杠
  /// 都会失败。改动这里就必须同步改 Developer Portal → Login Kit → Web。
  /// 服务器上 `/tiktok-callback/` 和 `/tiktok-callback/index.html` 返回的是
  /// 同一个文件，但 OAuth 比对的是字符串，不是最终资源。
  static const String tiktokRedirectUri =
      'https://tv.qahwatv.com/tiktok-callback/index.html';

  /// 授权 URL 是否带 PKCE（`code_challenge` + `code_challenge_method=S256`）。
  ///
  /// 【默认 false —— 与官方 Web 文档保持一致】
  ///
  /// 官方 Login Kit for Web 文档规定的必备参数只有 5 个
  /// （`client_key` / `scope` / `redirect_uri` / `state` / `response_type`），
  /// 没有 PKCE。TikTok 授权页自己的 `authV2.js` 也只在「来自原生 SDK」和
  /// 「redirect_uri 是 localhost/127.0.0.1（Desktop 流）」两个分支里写
  /// `code_challenge`；普通 Web 分支不写。
  ///
  /// 本项目已就 PKCE 做过三轮对照，结论都是「带上与否结果完全一致」：
  ///   1. 已登录态、同一 WebView 逐项对照（V0 带 / V1 不带 / V3 plain）
  ///   2. 官方 OpenSDK 2.4.0 自己生成的、**带 code_challenge** 的 URL 也被拒
  ///   3. 真实构建带 PKCE 跑真机，错误一字不差
  /// 详见 `docs/deployment/tiktok-diagnosis.md`。
  ///
  /// 所以默认关闭，让请求回到文档规定的精确形态 —— 这样万一再报错，
  /// 「多传了不支持参数」（10002）这一可能也被排除掉。
  ///
  /// 【开启时注意】实现是完整的：verifier 用 [Random.secure] 生成 48 字节、
  /// base64url 去 padding（64 字符，落在 RFC 7636 的 unreserved 字符集内），
  /// challenge 用 **SHA-256 的小写十六进制**（64 字符，TikTok 要求的格式，
  /// 不是标准 OAuth 的 base64url）。verifier 会经 [TiktokLoginResult] 原样
  /// 透传给后端，后端换 token 时必须带上，否则 `invalid_grant`。
  static const bool tiktokUsePkce = false;

  static const Duration tiktokLoginTimeout = Duration(minutes: 5);
}
