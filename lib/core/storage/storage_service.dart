import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

import '../../core/constants/app_constants.dart';

/// ============================================================================
/// 本地存储服务
///
/// 【功能说明】
/// 提供应用数据的本地存储功能，使用混合存储策略：
/// - SharedPreferences：存储一般配置数据（主题、语言、搜索历史等）
/// - FlutterSecureStorage：存储敏感数据（认证令牌、用户信息等）
///
/// 【存储内容】
/// - 用户认证令牌（安全存储）
/// - 用户个人数据（安全存储）
/// - 应用主题设置
/// - 应用语言设置
/// - 观看历史记录
/// - 收藏列表
/// - 下载管理
///
/// 【如何修改】
/// - 新增存储字段：在对应分类下添加新的方法
/// - 修改存储格式：确保 jsonEncode/jsonDecode 的数据结构一致
/// ============================================================================
class StorageService {
  static const String _userTokenKey = 'user_token';
  static const String _userDataKey = 'user_data';
  static const String _authTokenKey = 'auth_token';
  // 单例模式：确保全局只有一个 StorageService 实例
  static final StorageService _instance = StorageService._internal();

  /// 获取单例实例
  factory StorageService() => _instance;

  /// 私有构造函数，用于实现单例
  StorageService._internal();

  // ==================== 存储介质初始化 ====================
  /// FlutterSecureStorage 实例，用于安全存储（加密存储）
  /// 【说明】数据会以加密形式存储在设备上，适合存储敏感信息
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// SharedPreferences 实例，用于普通存储
  /// 【说明】数据以明文形式存储，适合存储非敏感配置信息
  SharedPreferences? _prefs;

  /// 初始化存储服务
  /// 【调用时机】在 main.dart 中应用启动时调用
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      // 初始化成功提示：可在开发时取消注释查看
      // print('StorageService initialized successfully');
    } catch (e) {
      debugPrint('StorageService init failed: $e');
    }
  }

  // ==================== 通用 String 存储 (SharedPreferences) ====================
  /// 保存字符串到本地存储
  /// [key] 存储键名
  /// [value] 要存储的字符串值
  Future<void> setString(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  /// 从本地存储读取字符串
  /// [key] 存储键名
  /// 返回存储的值，如果不存在则返回 null
  String? getString(String key) {
    return _prefs?.getString(key);
  }

  /// 删除指定键名的存储数据
  /// [key] 要删除的存储键名
  Future<void> remove(String key) async {
    await _prefs?.remove(key);
  }

  /// 清空所有 SharedPreferences 数据
  /// 【注意】这不会清除 FlutterSecureStorage 中的数据
  Future<void> clear() async {
    await _prefs?.clear();
  }

  // ==================== 认证令牌管理 (Secure Storage) ====================
  /// 【重要】这些方法使用加密存储，适合存储认证令牌等敏感信息

  /// 保存认证令牌（Firebase ID token / 第三方登录辅助凭证）
  /// [token] JWT 认证令牌
  /// 【调用时机】用户登录成功时调用
  Future<void> saveAuthToken(String token) async {
    await _secureStorage.write(key: _authTokenKey, value: token);
    if (kIsWeb) {
      await _prefs?.setString(_authTokenKey, token);
    }
  }

  /// 读取认证令牌（异步方式）
  /// 【说明】FlutterSecureStorage 不支持同步读取，必须使用异步方法
  Future<String?> getAuthTokenAsync() async {
    try {
      final secureValue = await _secureStorage.read(key: _authTokenKey);
      if (secureValue != null && secureValue.isNotEmpty) {
        return secureValue;
      }
    } catch (_) {}
    return _prefs?.getString(_authTokenKey);
  }

  /// 清除认证令牌
  /// 【说明】这里只清理 auth_token；user_token 由 removeToken() 或更高层登出流程单独清理。
  /// 【调用时机】Firebase / 第三方登录态失效时调用
  Future<void> clearAuthToken() async {
    await _secureStorage.delete(key: _authTokenKey);
    if (kIsWeb) {
      await _prefs?.remove(_authTokenKey);
    }
  }

  // ==================== 设备 UUID 管理 (Secure Storage) ====================
  /// 保存设备 UUID（用于游客登录标识设备）
  Future<void> saveDeviceUuid(String uuid) async {
    await _secureStorage.write(key: 'device_uuid', value: uuid);
  }

  /// 读取设备 UUID
  Future<String?> getDeviceUuid() async {
    try {
      return await _secureStorage.read(key: 'device_uuid');
    } catch (_) {
      return null;
    }
  }

  // ==================== 用户令牌管理 (Secure Storage) ====================
  /// 保存用户令牌（后端业务接口真正使用的 token）。
  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _userTokenKey, value: token);
    if (kIsWeb) {
      await _prefs?.setString(_userTokenKey, token);
    }
    debugPrint('[StorageService] saveToken web=$kIsWeb hasPrefs=${_prefs != null}');
  }

  /// 读取用户令牌
  Future<String?> getToken() async {
    try {
      final secureValue = await _secureStorage.read(key: _userTokenKey);
      if (secureValue != null && secureValue.isNotEmpty) {
        debugPrint('[StorageService] getToken from secure storage web=$kIsWeb');
        return secureValue;
      }
    } catch (_) {}
    final prefsValue = _prefs?.getString(_userTokenKey);
    debugPrint('[StorageService] getToken fallback prefsHit=${prefsValue != null && prefsValue.isNotEmpty} web=$kIsWeb');
    return prefsValue;
  }

  /// 删除用户令牌
  Future<void> removeToken() async {
    await _secureStorage.delete(key: _userTokenKey);
    if (kIsWeb) {
      await _prefs?.remove(_userTokenKey);
    }
  }

  // ==================== 用户数据管理 (Secure Storage) ====================
  /// 保存用户个人数据
  /// [userData] 用户数据 Map，包含用户信息字段
  /// 【调用时机】用户登录成功或更新个人信息时调用
  Future<void> saveUserData(Map<String, dynamic> userData) async {
    final jsonString = jsonEncode(userData);
    await _secureStorage.write(key: _userDataKey, value: jsonString);
    if (kIsWeb) {
      await _prefs?.setString(_userDataKey, jsonString);
    }
  }

  /// 读取用户个人数据
  /// 返回用户数据的 Map，如果不存在则返回 null
  Future<Map<String, dynamic>?> getUserData() async {
    String? jsonString;
    try {
      jsonString = await _secureStorage.read(key: _userDataKey);
    } catch (_) {}
    jsonString ??= _prefs?.getString(_userDataKey);
    if (jsonString != null) {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    }
    return null;
  }

  /// 删除用户个人数据
  /// 【调用时机】用户登出时调用
  Future<void> removeUserData() async {
    await _secureStorage.delete(key: _userDataKey);
    if (kIsWeb) {
      await _prefs?.remove(_userDataKey);
    }
  }

  // ==================== 语言偏好设置 (SharedPreferences) ====================
  /// 保存用户选择的语言
  /// [languageCode] 语言代码，如 'en'（英语）、'ar'（阿拉伯语）
  /// 【调用时机】用户更改应用语言设置时调用
  Future<void> saveLanguage(String languageCode) async {
    await _prefs?.setString('language_code', languageCode);
  }

  /// 读取用户选择的语言
  /// 返回语言代码，如果未设置则返回 null
  Future<String?> getLanguage() async {
    return _prefs?.getString('language_code');
  }

  // ==================== 主题偏好设置 (SharedPreferences) ====================
  /// 保存主题模式设置
  /// [isDarkMode] true 表示暗色模式，false 表示亮色模式
  /// 【调用时机】用户切换主题时调用
  Future<void> saveThemeMode(bool isDarkMode) async {
    await _prefs?.setBool('is_dark_mode', isDarkMode);
  }

  /// 读取主题模式设置
  /// 返回是否使用暗色模式，默认 false（亮色模式）
  Future<bool> getThemeMode() async {
    return _prefs?.getBool('is_dark_mode') ?? false;
  }

  // ==================== 播放进度持久化 ====================
  /// 保存视频播放进度
  /// [videoId] 视频 ID
  /// [positionMs] 当前播放位置（毫秒）
  /// [durationMs] 视频总时长（毫秒）
  Future<void> saveVideoProgress(String videoId, int positionMs, int durationMs) async {
    final all = await getAllVideoProgress();
    all[videoId] = {
      'positionMs': positionMs,
      'durationMs': durationMs,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    await _prefs?.setString(_keyVideoProgress, jsonEncode(all));
  }

  /// 读取指定视频的播放进度
  /// 返回 positionMs（毫秒），未找到返回 0
  Future<int> getVideoProgress(String videoId) async {
    final all = await getAllVideoProgress();
    return all[videoId]?['positionMs'] as int? ?? 0;
  }

  /// 读取指定视频的完整进度信息
  /// 返回 {positionMs, durationMs, lastUpdated}，未找到返回 null
  Future<Map<String, dynamic>?> getVideoProgressInfo(String videoId) async {
    final all = await getAllVideoProgress();
    return all[videoId] as Map<String, dynamic>?;
  }

  /// 读取所有视频播放进度
  Future<Map<String, dynamic>> getAllVideoProgress() async {
    final jsonString = _prefs?.getString(_keyVideoProgress);
    if (jsonString != null) {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    }
    return {};
  }

  /// 删除指定视频的播放进度
  Future<void> removeVideoProgress(String videoId) async {
    final all = await getAllVideoProgress();
    all.remove(videoId);
    await _prefs?.setString(_keyVideoProgress, jsonEncode(all));
  }

  static const String _keyVideoProgress = 'video_progress';

  // ==================== 观看历史记录 (SharedPreferences) ====================
  /// 添加内容到观看历史
  /// [item] 要添加的内容数据，必须包含 'id' 字段
  /// 【功能特点】
  /// - 如果内容已存在，会将其移到历史最前面
  /// - 最多保留 100 条历史记录
  /// - 自动记录观看时间戳
  Future<void> addToWatchHistory(Map<String, dynamic> item) async {
    final history = await getWatchHistory();
    // 检查内容是否已存在
    final existingIndex = history.indexWhere((e) => e['id'] == item['id']);
    if (existingIndex != -1) {
      // 已存在则移除旧记录
      history.removeAt(existingIndex);
    }
    // 在最前面插入新记录
    history.insert(0, {
      ...item,
      'date': DateTime.now().toIso8601String(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    // 限制历史记录数量
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }
    await _prefs?.setString('watch_history', jsonEncode(history));
  }

  /// 获取观看历史记录列表
  /// 返回按观看时间倒序排列的历史记录
  Future<List<Map<String, dynamic>>> getWatchHistory() async {
    final jsonString = _prefs?.getString('watch_history');
    if (jsonString != null) {
      final list = jsonDecode(jsonString) as List;
      return list.map((e) => e as Map<String, dynamic>).toList();
    }
    return [];
  }

  /// 清空所有观看历史
  /// 【调用时机】用户手动清除历史或登出时调用
  Future<void> clearWatchHistory() async {
    await _prefs?.remove('watch_history');
  }

  // ==================== 收藏列表 (SharedPreferences) ====================
  /// 添加内容到收藏列表
  /// [item] 要收藏的内容数据，必须包含 'id' 字段
  /// 【功能特点】
  /// - 同一内容不会重复添加
  /// - 自动记录收藏时间
  Future<void> addFavorite(Map<String, dynamic> item) async {
    final favorites = await getFavorites();
    // 检查是否已收藏
    final existingIndex = favorites.indexWhere((e) => e['id'] == item['id']);
    if (existingIndex == -1) {
      // 未收藏则添加到列表最前面
      favorites.insert(0, {
        ...item,
        'addedAt': DateTime.now().toIso8601String(),
      });
      await _prefs?.setString('favorites', jsonEncode(favorites));
    }
  }

  /// 获取收藏列表
  /// 返回按收藏时间倒序排列的收藏内容
  Future<List<Map<String, dynamic>>> getFavorites() async {
    final jsonString = _prefs?.getString('favorites');
    if (jsonString != null) {
      final list = jsonDecode(jsonString) as List;
      return list.map((e) => e as Map<String, dynamic>).toList();
    }
    return [];
  }

  /// 从收藏列表移除指定内容
  /// [id] 要移除的内容 ID
  Future<void> removeFavorite(String id) async {
    final favorites = await getFavorites();
    favorites.removeWhere((e) => e['id'] == id);
    await _prefs?.setString('favorites', jsonEncode(favorites));
  }

  /// 检查内容是否已收藏
  /// [id] 内容 ID
  /// 返回 true 表示已收藏，false 表示未收藏
  Future<bool> isFavorite(String id) async {
    final favorites = await getFavorites();
    return favorites.any((e) => e['id'] == id);
  }

  // ==================== 下载管理 (SharedPreferences) ====================
  /// 添加下载记录
  /// [item] 下载内容数据，必须包含 'id' 字段
  /// 【功能特点】
  /// - 同一内容不会重复添加
  /// - 自动记录下载完成时间
  /// - 默认状态为 'completed'
  Future<void> addDownload(Map<String, dynamic> item) async {
    final downloads = await getDownloads();
    // 检查是否已下载
    final existingIndex = downloads.indexWhere((e) => e['id'] == item['id']);
    if (existingIndex == -1) {
      downloads.add({
        ...item,
        'downloadedAt': DateTime.now().toIso8601String(),
        'status': 'completed',
      });
      await _prefs?.setString('downloads', jsonEncode(downloads));
    }
  }

  /// 获取下载列表
  /// 返回所有已下载的内容
  Future<List<Map<String, dynamic>>> getDownloads() async {
    final jsonString = _prefs?.getString('downloads');
    if (jsonString != null) {
      final list = jsonDecode(jsonString) as List;
      return list.map((e) => e as Map<String, dynamic>).toList();
    }
    return [];
  }

  /// 删除下载记录
  /// [id] 要删除的下载内容 ID
  /// 【注意】这只是删除记录，不会删除实际的文件
  Future<void> removeDownload(String id) async {
    final downloads = await getDownloads();
    downloads.removeWhere((e) => e['id'] == id);
    await _prefs?.setString('downloads', jsonEncode(downloads));
  }

  // ==================== 清除所有数据 ====================
  /// 清空所有存储数据
  /// 【调用时机】
  /// - 用户注销账户时
  /// - 应用重置/恢复出厂设置时
  /// 【注意】这会同时清空 SharedPreferences 和 FlutterSecureStorage 的所有数据
  Future<void> clearAllData() async {
    await _prefs?.clear();
    await _secureStorage.deleteAll();
  }

  // ==================== 系统配置缓存 ====================
  /// 保存系统配置（从后端获取）
  Future<void> saveSystemConfig(Map<String, dynamic> config) async {
    await _prefs?.setString('system_config_linekong', jsonEncode(config));
  }

  /// 读取系统配置
  Future<Map<String, dynamic>?> getSystemConfig() async {
    final jsonString = _prefs?.getString('system_config_linekong');
    if (jsonString != null) {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    }
    return null;
  }

  // ==================== K币/解锁提示状态 ====================
  /// K币充值不再提示
  Future<void> saveKCionAgreeMore(bool agreed) async {
    await _prefs?.setBool('k_cion_agree_more_linekong', agreed);
  }

  Future<bool> getKCionAgreeMore() async {
    return _prefs?.getBool('k_cion_agree_more_linekong') ?? false;
  }

  /// 解锁剧集不再提示
  Future<void> saveEpisodeUnlock(bool agreed) async {
    await _prefs?.setBool('episode_unlock_linekong', agreed);
  }

  Future<bool> getEpisodeUnlock() async {
    return _prefs?.getBool('episode_unlock_linekong') ?? false;
  }

  // ==================== 自动登录 (SharedPreferences) ====================
  /// 保存自动登录开关状态
  Future<void> saveAutoLogin(bool enabled) async {
    await _prefs?.setBool(AppConstants.autoLoginKey, enabled);
  }

  /// 读取自动登录开关状态
  Future<bool> getAutoLogin() async {
    return _prefs?.getBool(AppConstants.autoLoginKey) ?? false;
  }

  /// 保存自动登录记住的邮箱
  Future<void> saveAutoLoginEmail(String email) async {
    await _prefs?.setString(AppConstants.autoLoginEmailKey, email);
  }

  /// 读取自动登录记住的邮箱
  Future<String?> getAutoLoginEmail() async {
    return _prefs?.getString(AppConstants.autoLoginEmailKey);
  }

  /// 保存自动登录记住的密码（安全存储）
  Future<void> saveAutoLoginPassword(String password) async {
    await _secureStorage.write(key: AppConstants.autoLoginPasswordKey, value: password);
  }

  /// 读取自动登录记住的密码
  Future<String?> getAutoLoginPassword() async {
    return await _secureStorage.read(key: AppConstants.autoLoginPasswordKey);
  }

  /// 保存自动登录时间戳（30天有效期）
  Future<void> saveAutoLoginTimestamp() async {
    await _prefs?.setInt(AppConstants.autoLoginTimestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// 读取自动登录时间戳
  int? getAutoLoginTimestamp() {
    return _prefs?.getInt(AppConstants.autoLoginTimestampKey);
  }

  /// 自动登录凭证是否在30天有效期内
  bool isAutoLoginValid() {
    final ts = getAutoLoginTimestamp();
    if (ts == null) return false;
    final saved = DateTime.fromMillisecondsSinceEpoch(ts);
    final diff = DateTime.now().difference(saved).inDays;
    return diff <= 30;
  }

  /// 清除自动登录记住的凭证
  Future<void> clearAutoLoginCredentials() async {
    await _prefs?.remove(AppConstants.autoLoginKey);
    await _prefs?.remove(AppConstants.autoLoginEmailKey);
    await _prefs?.remove(AppConstants.autoLoginTimestampKey);
    await _secureStorage.delete(key: AppConstants.autoLoginPasswordKey);
  }
}
