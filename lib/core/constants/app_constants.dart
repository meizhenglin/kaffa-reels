/// ============================================================================
/// 应用全局常量配置文件
///
/// 【功能说明】
/// 定义应用中使用的各种常量值，包括：API 地址、超时时间、存储键名、
/// 支持的语言、阿里云播放器配置等。
///
/// 【如何修改】
/// - API 地址：在生产环境部署时替换 `apiBaseUrl`
/// - 超时时间：根据网络环境调整 `connectTimeout` 和 `receiveTimeout`
/// - 阿里云 License：替换 `aliPlayerLicenseKey` 为你的阿里云控制台申请的 License Key
/// ============================================================================
class AppConstants {
  // 私有构造函数，防止外部实例化
  AppConstants._();

  // ==================== 应用基础信息 ====================
  /// 应用名称，显示在启动页和关于页面
  static const String appName = 'Arabic Drama';

  // ==================== API 配置 ====================
  /// API 服务器基础地址，所有 API 请求都会基于此地址
  /// 【修改提示】部署到生产环境时替换为实际的服务器地址
  /// 注意：API 地址请在 AppConfig (core/config/app_config.dart) 中修改
  static const String apiBaseUrl = 'https://xemphimhay.vn';

  /// 连接超时时间（毫秒），请求超过此时间未响应则视为连接失败
  /// 【修改提示】网络较差时可适当增大此值
  static const int connectTimeout = 30000;

  /// 接收超时时间（毫秒），等待服务器响应数据的最大时间
  static const int receiveTimeout = 30000;

  // ==================== 本地存储键名 ====================
  /// SharedPreferences 存储的键名定义
  /// 【修改提示】如果需要更改存储逻辑，确保所有相关代码使用相同的键名

  /// 认证令牌（JWT）的存储键名
  static const String tokenKey = 'auth_token';
  /// 刷新令牌的存储键名
  static const String refreshTokenKey = 'refresh_token';
  /// 用户缓存数据的键名
  static const String userCacheKey = 'cached_user';
  /// 搜索历史记录的键名
  static const String searchHistoryKey = 'search_history';
  /// 最多保存的搜索历史条目数量
  static const int maxSearchHistoryItems = 10;
  /// 应用语言设置的键名
  static const String localeKey = 'app_locale';
  /// 设备语言设置的键名（游客登录时获取并存储，用于 X-Client header）
  static const String deviceLangKey = 'device_lang';
  /// App 重启标记（切换语言后设为 true，main.dart 检测到后重新 runApp）
  static const String restartAppKey = 'app_need_restart';
  /// 应用主题模式设置的键名（亮色/暗色）
  static const String themeModeKey = 'theme_mode';

  /// 客户端参数（投放平台传入）
  static const String clientParamsKey = 'client_params_linekong';
  /// 设备系统名称
  static const String osNameKey = 'os_name_linekong';
  /// K币充值不再提示
  static const String kCionAgreeMoreKey = 'k_cion_agree_more_linekong';
  /// 解锁剧集不再提示
  static const String episodeUnlockKey = 'episode_unlock_linekong';
  /// 系统配置缓存
  static const String systemConfigKey = 'system_config_linekong';

  /// 自动登录开关
  static const String autoLoginKey = 'auto_login';
  /// 自动登录记住的邮箱
  static const String autoLoginEmailKey = 'auto_login_email';
  /// 自动登录记住的密码（加密存储）
  static const String autoLoginPasswordKey = 'auto_login_password';
  /// 自动登录保存时间戳（毫秒）
  static const String autoLoginTimestampKey = 'auto_login_timestamp';

  // ==================== 国际化配置 ====================
  /// 支持的应用语言列表
  /// 【添加新语言】在此列表中添加新的语言代码（如 'fr', 'zh'）
  static const List<String> supportedLocales = ['en', 'ar'];
  /// 默认应用语言，当用户未设置时使用英语
  static const String defaultLocale = 'en';

  // ==================== 阿里云播放器配置 ====================
  /// 阿里云播放器 License Key
  /// 【重要】必须替换为在阿里云视频点播控制台申请的 License Key
  /// 申请地址：https://help.aliyun.com/document_detail/125570.html
  static const String aliPlayerLicenseKey = 'YOUR_ALIYUN_LICENSE_KEY';

  /// 阿里云播放器 License 证书文件路径
  /// 【修改提示】如果证书文件位置变化，在此修改路径
  static const String aliPlayerLicenseFile = 'assets/cert/license.crt';

  // ==================== 测试/示例数据 ====================
  /// 测试视频地址（HLS m3u8 流地址，用于开发阶段验证播放器功能）
  /// 【修改提示】替换为你自己的视频 URL
  static const String testVideoUrl =
      'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8';
}
