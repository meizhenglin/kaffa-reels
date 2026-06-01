import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/storage_service.dart';

/// ============================================================================
/// 全局 Provider 配置文件
///
/// 【功能说明】
/// 定义应用中使用的全局 Provider（状态管理单元），包括：
/// - StorageService：本地存储服务单例
/// - DioClient：HTTP 客户端单例
/// - ThemeModeProvider：主题模式状态管理
/// - LocaleProvider：语言/地区状态管理
///
/// 【架构说明】
/// 使用 Riverpod 进行状态管理，所有 Provider 都是全局单例
/// 这些 Provider 可以在应用的任何地方通过 ref.watch() 或 ref.read() 访问
///
/// 【如何修改】
/// - 添加新 Provider：在下面添加新的 Provider 定义
/// - 修改 Provider 逻辑：修改对应的 Notifier 类
/// ============================================================================

// ==================== 存储服务 Provider ====================
/// 本地存储服务 Provider
///
/// 【功能】提供 StorageService 单例实例
/// 【使用场景】
/// - 保存/读取用户设置（主题、语言）
/// - 管理观看历史、收藏列表
/// - 存储认证令牌等敏感信息
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

// ==================== HTTP 客户端 Provider ====================
/// HTTP 网络请求客户端 Provider
///
/// 【功能】提供 DioClient 单例实例
/// 【使用场景】
/// - 所有 API 请求都通过此客户端发送
/// - 已在内部配置好日志拦截器和认证头部
final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient();
});

// ==================== 主题模式 Provider ====================
/// 应用主题模式状态 Provider
///
/// 【功能】管理应用的主题模式（亮色/暗色/跟随系统）
/// 【数据类型】ThemeMode（system / light / dark）
///
/// 【使用场景】
/// - 切换应用主题时调用 ref.read(themeModeProvider.notifier).setThemeMode()
/// - 监听主题变化时使用 ref.watch(themeModeProvider)
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref);
});

// ==================== 语言/地区 Provider ====================
/// 应用语言/地区状态 Provider
///
/// 【功能】管理应用的语言设置
/// 【数据类型】Locale（如 Locale('en'), Locale('ar')）
///
/// 【使用场景】
/// - 切换应用语言时调用 ref.read(localeProvider.notifier).setLocale()
/// - 监听语言变化时使用 ref.watch(localeProvider)
final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier(ref);
});

/// ============================================================================
/// 主题模式状态管理器
///
/// 【功能】处理主题模式的读取、保存和切换逻辑
///
/// 【状态说明】
/// - ThemeMode.system：跟随系统设置
/// - ThemeMode.light：始终使用亮色主题
/// - ThemeMode.dark：始终使用暗色主题
/// ============================================================================
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  /// 构造函数，默认使用跟随系统设置
  ThemeModeNotifier(this._ref) : super(ThemeMode.system);

  final Ref _ref;

  /// 设置主题模式
  /// [mode] 要设置的主题模式
  ///
  /// 【调用时机】用户在设置页面切换主题时
  Future<void> setThemeMode(ThemeMode mode) async {
    // 1. 更新内存中的状态
    state = mode;
    // 2. 持久化保存到本地存储
    final storage = _ref.read(storageServiceProvider);
    await storage.setString('theme_mode', mode.name);
  }

  /// 从本地存储加载主题模式
  ///
  /// 【调用时机】应用启动时（在 main.dart 中调用）
  Future<void> load() async {
    final storage = _ref.read(storageServiceProvider);
    final value = storage.getString('theme_mode');
    if (value != null) {
      // 将字符串转换为 ThemeMode 枚举值
      // 如果转换失败则使用默认值 ThemeMode.system
      state = ThemeMode.values.firstWhere(
        (e) => e.name == value,
        orElse: () => ThemeMode.system,
      );
    }
  }
}

/// ============================================================================
/// 当前可见的 Tab 索引，用于播放器控制
/// 0=首页, 1=发现, 2=推荐, 3=游戏, 4=我的
final visibleTabIndexProvider = StateProvider<int>((ref) => 2);

/// 语言/地区状态管理器
///
/// 【功能】处理应用语言的读取、保存和切换逻辑
///
/// 【支持的语种】
/// - 'en'：英语（默认）
/// - 'ar'：阿拉伯语
///
/// 【RTL 支持】阿拉伯语是 RTL（从右到左）语言，UI 会自动翻转
/// ============================================================================
class LocaleNotifier extends StateNotifier<Locale> {
  /// 构造函数，默认使用英语
  LocaleNotifier(this._ref) : super(const Locale('en'));

  final Ref _ref;

  /// 设置应用语言
  /// [locale] 要设置的语言地区（如 Locale('en'), Locale('ar')）
  ///
  /// 【调用时机】用户在设置页面切换语言时
  Future<void> setLocale(Locale locale) async {
    // 1. 更新内存中的状态
    state = locale;
    // 2. 持久化保存到本地存储
    final storage = _ref.read(storageServiceProvider);
    await storage.setString('app_locale', locale.languageCode);
    // 3. 同步更新 deviceLangKey，下次请求的 X-Client header 立即生效
    await storage.setString(AppConstants.deviceLangKey, locale.languageCode);
    // 4. 标记需要重启 App，让 main() 重新初始化所有 Provider 和接口
    await storage.setString(AppConstants.restartAppKey, 'true');
  }

  /// 将 Flutter Locale 格式化为 X-Client header 所需格式
  String _formatLangCode(Locale locale) {
    // 格式如 "en" / "ar"
    return locale.languageCode;
  }

  /// 从本地存储加载语言设置
  ///
  /// 【调用时机】应用启动时（在 main.dart 中调用）
  Future<void> load() async {
    final storage = _ref.read(storageServiceProvider);
    final code = storage.getString('app_locale');
    if (code != null) {
      // 从存储的语言代码创建 Locale 对象
      state = Locale(code);
    }
  }
}
